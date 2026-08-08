local socket = require "cosock.socket"
local json = require "st.json"

local crypto = require "miio_crypto"

local rpc = {}

local MIIO_PORT = 54321
local MIIO_HELLO =
  string.char(0x21, 0x31, 0x00, 0x20) ..
  string.rep(string.char(0xff), 28)

local sequence = 0

local function close_socket(sock)
  if sock then
    pcall(function()
      sock:close()
    end)
  end
end

local function u16_be(value)
  return string.char(
    (value >> 8) & 0xff,
    value & 0xff
  )
end

local function u32_be_bytes(value)
  return string.char(
    (value >> 24) & 0xff,
    (value >> 16) & 0xff,
    (value >> 8) & 0xff,
    value & 0xff
  )
end

local function u16_be_read(data, offset)
  local b1, b2 = data:byte(offset, offset + 1)
  if not b2 then
    return nil
  end
  return (b1 << 8) | b2
end

local function u32_be_read(data, offset)
  local b1, b2, b3, b4 = data:byte(offset, offset + 3)
  if not b4 then
    return nil
  end
  return (((b1 * 256) + b2) * 256 + b3) * 256 + b4
end

local function next_id()
  sequence = sequence + 1
  if sequence >= 9999 then
    sequence = 1
  end
  return sequence
end

local function valid_token_hex(value)
  if type(value) ~= "string" then
    return false
  end

  value = value:match("^%s*(.-)%s*$")
  return
    #value == 32 and
    value:match("^[0-9a-fA-F]+$") ~= nil
end

local function candidate_token(checksum)
  if #checksum ~= 16 then
    return nil
  end

  if checksum == string.rep(string.char(0xff), 16) then
    return nil
  end

  if checksum == string.rep(string.char(0x00), 16) then
    return nil
  end

  return checksum
end

local function handshake(ip, timeout)
  local udp, create_error = socket.udp()
  if not udp then
    return nil, "unable to create UDP socket: " .. tostring(create_error)
  end

  udp:settimeout(timeout)

  local sent, send_error = udp:sendto(MIIO_HELLO, ip, MIIO_PORT)
  if not sent then
    close_socket(udp)
    return nil, "handshake send failed: " .. tostring(send_error)
  end

  local data, receive_error = udp:receivefrom()
  close_socket(udp)

  if not data then
    return nil, "handshake receive failed: " .. tostring(receive_error)
  end

  if #data < 32 then
    return nil, "short miIO handshake response"
  end

  if data:byte(1) ~= 0x21 or data:byte(2) ~= 0x31 then
    return nil, "invalid miIO handshake magic"
  end

  return {
    device_id = data:sub(9, 12),
    timestamp = u32_be_read(data, 13),
    checksum = data:sub(17, 32),
  }
end

function rpc.valid_token_hex(value)
  return valid_token_hex(value)
end

function rpc.call(ip, token_hex, method, params_or_timeout, timeout_seconds)
  if type(method) ~= "string" or
     method:match("^[%w_%.]+$") == nil then
    return false, {
      reason = "invalid miIO method",
    }
  end

  local params = {}
  local timeout_value = timeout_seconds

  -- Backward compatibility with v1.4.0:
  -- call(ip, token, method, timeout)
  if type(params_or_timeout) == "number" or params_or_timeout == nil then
    timeout_value = params_or_timeout
  else
    params = params_or_timeout
  end

  local timeout = tonumber(timeout_value) or 3
  if timeout < 1 then
    timeout = 1
  elseif timeout > 10 then
    timeout = 10
  end

  local hello, hello_error = handshake(ip, timeout)
  if not hello then
    return false, {
      reason = hello_error,
      method = method,
    }
  end

  local token
  local token_source

  if valid_token_hex(token_hex or "") then
    token = assert(crypto.hex_to_bytes(
      tostring(token_hex):match("^%s*(.-)%s*$")
    ))
    token_source = "preference"
  else
    token = candidate_token(hello.checksum)
    if token then
      token_source = "handshake"
    end
  end

  if not token then
    return false, {
      reason = "gateway token is required for authenticated miIO RPC",
      method = method,
      token_required = true,
    }
  end

  local request_id = next_id()

  local encode_ok, params_json = pcall(json.encode, params)
  if not encode_ok then
    return false, {
      reason = "unable to encode miIO params",
      method = method,
    }
  end

  local payload = string.format(
    '{"id":%d,"method":"%s","params":%s}',
    request_id,
    method,
    params_json
  ) .. string.char(0)

  local encrypted = crypto.miio_encrypt(payload, token)
  local packet_length = 32 + #encrypted

  local timestamp = (tonumber(hello.timestamp) or os.time()) + 1

  local header =
    string.char(0x21, 0x31) ..
    u16_be(packet_length) ..
    string.char(0x00, 0x00, 0x00, 0x00) ..
    hello.device_id ..
    u32_be_bytes(timestamp)

  local checksum = crypto.md5(header .. token .. encrypted)
  local packet = header .. checksum .. encrypted

  local udp, create_error = socket.udp()
  if not udp then
    return false, {
      reason = "unable to create UDP socket: " .. tostring(create_error),
      method = method,
    }
  end

  udp:settimeout(timeout)

  local sent, send_error = udp:sendto(packet, ip, MIIO_PORT)
  if not sent then
    close_socket(udp)
    return false, {
      reason = "RPC send failed: " .. tostring(send_error),
      method = method,
    }
  end

  local response, receive_error = udp:receivefrom()
  close_socket(udp)

  if not response then
    return false, {
      reason = "RPC receive failed: " .. tostring(receive_error),
      method = method,
    }
  end

  if #response < 32 then
    return false, {
      reason = "short authenticated miIO response",
      method = method,
    }
  end

  if response:byte(1) ~= 0x21 or response:byte(2) ~= 0x31 then
    return false, {
      reason = "invalid authenticated miIO response magic",
      method = method,
    }
  end

  local declared_length = u16_be_read(response, 3)
  if declared_length and declared_length > #response then
    return false, {
      reason = "truncated authenticated miIO response",
      method = method,
    }
  end

  local response_header = response:sub(1, 16)
  local response_checksum = response:sub(17, 32)
  local response_ciphertext = response:sub(33)

  local expected_checksum =
    crypto.md5(response_header .. token .. response_ciphertext)

  if response_checksum ~= expected_checksum then
    return false, {
      reason = "miIO checksum mismatch; gateway token may be invalid",
      method = method,
      invalid_token = true,
    }
  end

  local decrypted, decrypt_error =
    crypto.miio_decrypt(response_ciphertext, token)

  if not decrypted then
    return false, {
      reason = "miIO decrypt failed: " .. tostring(decrypt_error),
      method = method,
      invalid_token = true,
    }
  end

  decrypted = decrypted:gsub("%z+$", "")

  local decode_ok, decoded = pcall(json.decode, decrypted)
  if not decode_ok or type(decoded) ~= "table" then
    return false, {
      reason = "unable to decode miIO JSON response",
      method = method,
    }
  end

  if decoded.error then
    local error_code = decoded.error.code
    local error_message = decoded.error.message
    return false, {
      reason = string.format(
        "miIO error code=%s message=%s",
        tostring(error_code or ""),
        tostring(error_message or "")
      ),
      method = method,
      error = decoded.error,
    }
  end

  return true, {
    method = method,
    result = decoded.result,
    payload = decoded,
    token_source = token_source,
    device_id = u32_be_read(hello.device_id, 1),
    response_timestamp = u32_be_read(response, 13),
  }
end

return rpc
