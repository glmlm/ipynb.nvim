local M = {}

--- Pack a number as unsigned 8-bit integer
function M.pack_u8(n)
  return string.char(bit.band(n, 0xFF))
end

--- Pack a number as big-endian unsigned 16-bit integer
function M.pack_be_u16(n)
  return string.char(bit.band(bit.rshift(n, 8), 0xFF), bit.band(n, 0xFF))
end

--- Unpack big-endian unsigned 16-bit integer from string
function M.unpack_be_u16(s, pos)
  pos = pos or 1
  local b1, b2 = string.byte(s, pos, pos + 1)
  return bit.bor(bit.lshift(b1, 8), b2)
end

--- Pack a number as big-endian unsigned 32-bit integer
local function pack_be_u32(n)
  return string.char(
    bit.band(bit.rshift(n, 24), 0xFF),
    bit.band(bit.rshift(n, 16), 0xFF),
    bit.band(bit.rshift(n, 8), 0xFF),
    bit.band(n, 0xFF)
  )
end

--- Unpack big-endian unsigned 32-bit integer from string
local function unpack_be_u32(s, pos)
  pos = pos or 1
  local b1, b2, b3, b4 = string.byte(s, pos, pos + 3)
  return b1 * 0x1000000 + b2 * 0x10000 + b3 * 0x100 + b4
end

--- Pack a number as big-endian unsigned 64-bit integer
function M.pack_be_u64(n)
  local high = math.floor(n / 0x100000000)
  local low = n % 0x100000000
  return pack_be_u32(high) .. pack_be_u32(low)
end

--- Unpack big-endian unsigned 64-bit integer from string
function M.unpack_be_u64(s, pos)
  pos = pos or 1
  local high = unpack_be_u32(s, pos)
  local low = unpack_be_u32(s, pos + 4)
  return high * 0x100000000 + low
end

--- Compute SHA-1 hash of a message
function M.sha1(message)
  local function left_rotate(n, bits)
    return bit.bor(bit.lshift(n, bits), bit.rshift(n, 32 - bits))
  end

  local h0, h1, h2, h3, h4 = 0x67452301, 0xEFCDAB89, 0x98BADCFE, 0x10325476, 0xC3D2E1F0
  local len = #message
  local bit_len = len * 8
  message = message .. '\x80'
  while (#message % 64) ~= 56 do
    message = message .. '\0'
  end
  message = message .. M.pack_be_u64(bit_len)

  for i = 1, #message, 64 do
    local block = message:sub(i, i + 63)
    local w = {}
    for j = 1, 16 do
      local pos = (j - 1) * 4 + 1
      local b1, b2, b3, b4 = string.byte(block, pos, pos + 3)
      w[j] = bit.bor(bit.lshift(b1, 24), bit.lshift(b2, 16), bit.lshift(b3, 8), b4)
    end
    for j = 17, 80 do
      w[j] = left_rotate(bit.bxor(w[j - 3], w[j - 8], w[j - 14], w[j - 16]), 1)
    end
    local a, b, c, d, e = h0, h1, h2, h3, h4
    for j = 1, 80 do
      local f, k
      if j <= 20 then
        f = bit.bor(bit.band(b, c), bit.band(bit.bnot(b), d))
        k = 0x5A827999
      elseif j <= 40 then
        f = bit.bxor(b, c, d)
        k = 0x6ED9EBA1
      elseif j <= 60 then
        f = bit.bor(bit.band(b, c), bit.band(b, d), bit.band(c, d))
        k = 0x8F1BBCDC
      else
        f = bit.bxor(b, c, d)
        k = 0xCA62C1D6
      end
      local temp = (left_rotate(a, 5) + f + e + k + w[j]) % 0x100000000
      e = d
      d = c
      c = left_rotate(b, 30)
      b = a
      a = temp
    end
    h0 = (h0 + a) % 0x100000000
    h1 = (h1 + b) % 0x100000000
    h2 = (h2 + c) % 0x100000000
    h3 = (h3 + d) % 0x100000000
    h4 = (h4 + e) % 0x100000000
  end
  return pack_be_u32(h0) .. pack_be_u32(h1) .. pack_be_u32(h2) .. pack_be_u32(h3) .. pack_be_u32(h4)
end

return M
