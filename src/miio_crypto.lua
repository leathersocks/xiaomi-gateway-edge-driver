local crypto = {}

local function u32(x)
  return x & 0xffffffff
end

local function rol32(x, n)
  x = u32(x)
  return u32((x << n) | (x >> (32 - n)))
end

local MD5_S = {
  7,12,17,22, 7,12,17,22, 7,12,17,22, 7,12,17,22,
  5,9,14,20, 5,9,14,20, 5,9,14,20, 5,9,14,20,
  4,11,16,23, 4,11,16,23, 4,11,16,23, 4,11,16,23,
  6,10,15,21, 6,10,15,21, 6,10,15,21, 6,10,15,21,
}

local MD5_K = {}
for i = 1, 64 do
  MD5_K[i] =
    math.floor(math.abs(math.sin(i)) * 4294967296) & 0xffffffff
end

local function le32(bytes, i)
  return
    (bytes[i] or 0) |
    ((bytes[i + 1] or 0) << 8) |
    ((bytes[i + 2] or 0) << 16) |
    ((bytes[i + 3] or 0) << 24)
end

local function append_le32(out, x)
  x = u32(x)
  out[#out + 1] = string.char(
    x & 0xff,
    (x >> 8) & 0xff,
    (x >> 16) & 0xff,
    (x >> 24) & 0xff
  )
end

function crypto.md5(data)
  local bytes = { data:byte(1, #data) }
  local bit_len = #data * 8

  bytes[#bytes + 1] = 0x80
  while (#bytes % 64) ~= 56 do
    bytes[#bytes + 1] = 0
  end

  local low = bit_len & 0xffffffff
  local high = math.floor(bit_len / 4294967296) & 0xffffffff

  for shift = 0, 24, 8 do
    bytes[#bytes + 1] = (low >> shift) & 0xff
  end
  for shift = 0, 24, 8 do
    bytes[#bytes + 1] = (high >> shift) & 0xff
  end

  local a0 = 0x67452301
  local b0 = 0xefcdab89
  local c0 = 0x98badcfe
  local d0 = 0x10325476

  for offset = 1, #bytes, 64 do
    local words = {}
    for j = 0, 15 do
      words[j] = u32(le32(bytes, offset + (j * 4)))
    end

    local a, b, c, d = a0, b0, c0, d0

    for i = 0, 63 do
      local f, g

      if i <= 15 then
        f = (b & c) | ((~b) & d)
        g = i
      elseif i <= 31 then
        f = (d & b) | ((~d) & c)
        g = ((5 * i) + 1) % 16
      elseif i <= 47 then
        f = b ~ c ~ d
        g = ((3 * i) + 5) % 16
      else
        f = c ~ (b | (~d))
        g = (7 * i) % 16
      end

      f = u32(f)

      local old_d = d
      d = c
      c = b

      local sum = u32(a + f + MD5_K[i + 1] + words[g])
      b = u32(b + rol32(sum, MD5_S[i + 1]))
      a = old_d
    end

    a0 = u32(a0 + a)
    b0 = u32(b0 + b)
    c0 = u32(c0 + c)
    d0 = u32(d0 + d)
  end

  local out = {}
  append_le32(out, a0)
  append_le32(out, b0)
  append_le32(out, c0)
  append_le32(out, d0)
  return table.concat(out)
end

local function gf_mul(a, b)
  local value = 0

  for _ = 1, 8 do
    if (b & 1) ~= 0 then
      value = value ~ a
    end

    local high = a & 0x80
    a = (a << 1) & 0xff
    if high ~= 0 then
      a = a ~ 0x1b
    end

    b = b >> 1
  end

  return value & 0xff
end

local function gf_pow(a, n)
  local result = 1

  while n > 0 do
    if (n & 1) ~= 0 then
      result = gf_mul(result, a)
    end
    a = gf_mul(a, a)
    n = n >> 1
  end

  return result
end

local function rol8(x, n)
  return ((x << n) | (x >> (8 - n))) & 0xff
end

local SBOX = {}
local INV_SBOX = {}

for value = 0, 255 do
  local inverse = value == 0 and 0 or gf_pow(value, 254)
  local substituted =
    (inverse ~
      rol8(inverse, 1) ~
      rol8(inverse, 2) ~
      rol8(inverse, 3) ~
      rol8(inverse, 4) ~
      0x63) & 0xff

  SBOX[value] = substituted
  INV_SBOX[substituted] = value
end

local function expand_key(key)
  assert(#key == 16, "AES-128 key must be 16 bytes")

  local expanded = { key:byte(1, 16) }
  local generated = 16
  local round_constant = 1

  while generated < 176 do
    local temp = {
      expanded[generated - 3],
      expanded[generated - 2],
      expanded[generated - 1],
      expanded[generated],
    }

    if (generated % 16) == 0 then
      temp = {
        SBOX[temp[2]],
        SBOX[temp[3]],
        SBOX[temp[4]],
        SBOX[temp[1]],
      }
      temp[1] = temp[1] ~ round_constant
      round_constant = gf_mul(round_constant, 2)
    end

    for i = 1, 4 do
      expanded[generated + 1] =
        (expanded[generated - 15] ~ temp[i]) & 0xff
      generated = generated + 1
    end
  end

  return expanded
end

local function add_round_key(state, expanded, round)
  local base = round * 16

  for i = 1, 16 do
    state[i] = (state[i] ~ expanded[base + i]) & 0xff
  end
end

local function substitute_bytes(state, box)
  for i = 1, 16 do
    state[i] = box[state[i]]
  end
end

local function shift_rows(state, inverse)
  local shifted = {}

  for row = 0, 3 do
    for column = 0, 3 do
      local source_column
      if inverse then
        source_column = (column - row) % 4
      else
        source_column = (column + row) % 4
      end

      shifted[row + 1 + (4 * column)] =
        state[row + 1 + (4 * source_column)]
    end
  end

  for i = 1, 16 do
    state[i] = shifted[i]
  end
end

local function mix_columns(state, inverse)
  for column = 0, 3 do
    local i = 1 + (4 * column)
    local a0 = state[i]
    local a1 = state[i + 1]
    local a2 = state[i + 2]
    local a3 = state[i + 3]

    if not inverse then
      state[i] =
        gf_mul(a0, 2) ~ gf_mul(a1, 3) ~ a2 ~ a3
      state[i + 1] =
        a0 ~ gf_mul(a1, 2) ~ gf_mul(a2, 3) ~ a3
      state[i + 2] =
        a0 ~ a1 ~ gf_mul(a2, 2) ~ gf_mul(a3, 3)
      state[i + 3] =
        gf_mul(a0, 3) ~ a1 ~ a2 ~ gf_mul(a3, 2)
    else
      state[i] =
        gf_mul(a0, 14) ~ gf_mul(a1, 11) ~
        gf_mul(a2, 13) ~ gf_mul(a3, 9)
      state[i + 1] =
        gf_mul(a0, 9) ~ gf_mul(a1, 14) ~
        gf_mul(a2, 11) ~ gf_mul(a3, 13)
      state[i + 2] =
        gf_mul(a0, 13) ~ gf_mul(a1, 9) ~
        gf_mul(a2, 14) ~ gf_mul(a3, 11)
      state[i + 3] =
        gf_mul(a0, 11) ~ gf_mul(a1, 13) ~
        gf_mul(a2, 9) ~ gf_mul(a3, 14)
    end

    state[i] = state[i] & 0xff
    state[i + 1] = state[i + 1] & 0xff
    state[i + 2] = state[i + 2] & 0xff
    state[i + 3] = state[i + 3] & 0xff
  end
end

local function encrypt_block(block, expanded)
  local state = { block:byte(1, 16) }

  add_round_key(state, expanded, 0)

  for round = 1, 9 do
    substitute_bytes(state, SBOX)
    shift_rows(state, false)
    mix_columns(state, false)
    add_round_key(state, expanded, round)
  end

  substitute_bytes(state, SBOX)
  shift_rows(state, false)
  add_round_key(state, expanded, 10)

  return string.char(table.unpack(state))
end

local function decrypt_block(block, expanded)
  local state = { block:byte(1, 16) }

  add_round_key(state, expanded, 10)

  for round = 9, 1, -1 do
    shift_rows(state, true)
    substitute_bytes(state, INV_SBOX)
    add_round_key(state, expanded, round)
    mix_columns(state, true)
  end

  shift_rows(state, true)
  substitute_bytes(state, INV_SBOX)
  add_round_key(state, expanded, 0)

  return string.char(table.unpack(state))
end

local function xor_block(left, right)
  local out = {}

  for i = 1, 16 do
    out[i] = (left:byte(i) ~ right:byte(i)) & 0xff
  end

  return string.char(table.unpack(out))
end

function crypto.aes128_cbc_encrypt(data, key, iv)
  assert(#key == 16, "AES-128 key must be 16 bytes")
  assert(#iv == 16, "AES-CBC IV must be 16 bytes")

  local pad = 16 - (#data % 16)
  data = data .. string.rep(string.char(pad), pad)

  local expanded = expand_key(key)
  local previous = iv
  local out = {}

  for i = 1, #data, 16 do
    local mixed = xor_block(data:sub(i, i + 15), previous)
    local encrypted = encrypt_block(mixed, expanded)
    out[#out + 1] = encrypted
    previous = encrypted
  end

  return table.concat(out)
end

function crypto.aes128_cbc_decrypt(data, key, iv)
  if (#data % 16) ~= 0 then
    return nil, "ciphertext length is not a multiple of 16"
  end

  local expanded = expand_key(key)
  local previous = iv
  local out = {}

  for i = 1, #data, 16 do
    local block = data:sub(i, i + 15)
    local decrypted = xor_block(decrypt_block(block, expanded), previous)
    out[#out + 1] = decrypted
    previous = block
  end

  local plain = table.concat(out)
  if #plain == 0 then
    return nil, "empty plaintext"
  end

  local pad = plain:byte(-1)
  if not pad or pad < 1 or pad > 16 or pad > #plain then
    return nil, "bad PKCS7 padding"
  end

  for i = #plain - pad + 1, #plain do
    if plain:byte(i) ~= pad then
      return nil, "bad PKCS7 padding"
    end
  end

  return plain:sub(1, #plain - pad)
end

function crypto.hex_to_bytes(hex)
  if type(hex) ~= "string" then
    return nil, "not a string"
  end

  hex = hex:gsub("%s+", "")

  if (#hex % 2) ~= 0 or hex:find("[^0-9a-fA-F]") then
    return nil, "invalid hex"
  end

  local out = {}
  for i = 1, #hex, 2 do
    out[#out + 1] = string.char(tonumber(hex:sub(i, i + 1), 16))
  end

  return table.concat(out)
end

function crypto.bytes_to_hex(data)
  return (data:gsub(".", function(value)
    return string.format("%02x", string.byte(value))
  end))
end

function crypto.derive_key_iv(token)
  assert(#token == 16, "miIO token must be 16 bytes")
  local key = crypto.md5(token)
  local iv = crypto.md5(key .. token)
  return key, iv
end

function crypto.miio_encrypt(plaintext, token)
  local key, iv = crypto.derive_key_iv(token)
  return crypto.aes128_cbc_encrypt(plaintext, key, iv)
end

function crypto.miio_decrypt(ciphertext, token)
  local key, iv = crypto.derive_key_iv(token)
  return crypto.aes128_cbc_decrypt(ciphertext, key, iv)
end

-- Exposed only for deterministic package self-tests.
function crypto._aes_encrypt_block(block, key)
  return encrypt_block(block, expand_key(key))
end

function crypto._aes_decrypt_block(block, key)
  return decrypt_block(block, expand_key(key))
end

return crypto
