local socket = require "cosock.socket"

local probe = {}

local MIIO_PORT = 54321
local MIIO_HELLO =
  string.char(0x21, 0x31, 0x00, 0x20) ..
  string.rep(string.char(0xFF), 28)

local function close_socket(sock)
  if sock then
    pcall(function()
      sock:close()
    end)
  end
end

local function valid_ipv4(ip)
  if type(ip) ~= "string" then
    return false
  end

  local a, b, c, d = ip:match("^%s*(%d+)%.(%d+)%.(%d+)%.(%d+)%s*$")
  if not a then
    return false
  end

  local octets = { tonumber(a), tonumber(b), tonumber(c), tonumber(d) }
  for _, value in ipairs(octets) do
    if not value or value < 0 or value > 255 then
      return false
    end
  end

  return true
end

local function u32_be(data, offset)
  local b1, b2, b3, b4 = data:byte(offset, offset + 3)
  if not b4 then
    return nil
  end

  return (((b1 * 256) + b2) * 256 + b3) * 256 + b4
end

local function hex_bytes(data, first, last)
  local parts = {}

  for i = first, last do
    local value = data:byte(i)
    if not value then
      break
    end
    parts[#parts + 1] = string.format("%02x", value)
  end

  return table.concat(parts)
end

local function now_seconds()
  if type(socket.gettime) == "function" then
    return socket.gettime()
  end
  return os.time()
end

function probe.valid_ipv4(ip)
  return valid_ipv4(ip)
end

function probe.check(ip, timeout_seconds)
  if not valid_ipv4(ip) then
    return false, {
      reason = "invalid IPv4 address",
      ip = tostring(ip or ""),
      port = MIIO_PORT,
    }
  end

  local timeout = tonumber(timeout_seconds) or 3
  if timeout < 1 then
    timeout = 1
  elseif timeout > 10 then
    timeout = 10
  end

  local udp, create_error = socket.udp()
  if not udp then
    return false, {
      reason = "unable to create UDP socket: " .. tostring(create_error),
      ip = ip,
      port = MIIO_PORT,
    }
  end

  udp:settimeout(timeout)

  local started_at = now_seconds()
  local sent, send_error = udp:sendto(MIIO_HELLO, ip, MIIO_PORT)
  if not sent then
    close_socket(udp)
    return false, {
      reason = "send failed: " .. tostring(send_error),
      ip = ip,
      port = MIIO_PORT,
    }
  end

  local data, remote_ip_or_error, remote_port = udp:receivefrom()
  local finished_at = now_seconds()
  close_socket(udp)

  if not data then
    return false, {
      reason = tostring(remote_ip_or_error or "no response"),
      ip = ip,
      port = MIIO_PORT,
    }
  end

  if #data < 32 then
    return false, {
      reason = "short miIO response (" .. tostring(#data) .. " bytes)",
      ip = ip,
      port = MIIO_PORT,
    }
  end

  local magic1, magic2 = data:byte(1, 2)
  if magic1 ~= 0x21 or magic2 ~= 0x31 then
    return false, {
      reason = "response is not a miIO packet",
      ip = ip,
      port = MIIO_PORT,
    }
  end

  local latency_ms = math.max(
    0,
    math.floor(((finished_at - started_at) * 1000) + 0.5)
  )

  return true, {
    ip = tostring(remote_ip_or_error or ip),
    port = tonumber(remote_port) or MIIO_PORT,
    response_length = #data,
    device_id = hex_bytes(data, 9, 12),
    timestamp = u32_be(data, 13),
    latency_ms = latency_ms,
  }
end

return probe
