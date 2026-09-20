local M = {}

local bits = require('ipynb.webui.server.bits')

local function sha1_base64(key)
  local magic = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11'
  local combined = key .. magic
  local hash = bits.sha1(combined)
  return vim.base64.encode(hash)
end

--- Check if the request is a WebSocket upgrade request
function M.is_upgrade_request(data)
  return data:find('Upgrade: websocket', 1, true) ~= nil
end

--- Create WebSocket handshake response
function M.create_handshake_response(data)
  local key = data:match('Sec%-WebSocket%-Key:%s*(%S+)')
  if not key then
    return nil
  end

  local accept = sha1_base64(key)

  local resp = 'HTTP/1.1 101 Switching Protocols\r\n'
  resp = resp .. 'Upgrade: websocket\r\n'
  resp = resp .. 'Connection: Upgrade\r\n'
  resp = resp .. 'Sec-WebSocket-Accept: ' .. accept .. '\r\n'
  resp = resp .. '\r\n'

  return resp
end

--- Encode a WebSocket frame
--- @param data string The payload data
--- @param opcode number? Frame type (0x01=text, 0x02=binary, 0x08=close, 0x09=ping, 0x0A=pong)
function M.encode_frame(data, opcode)
  opcode = opcode or 0x01 -- Default text frame
  local len = #data

  local first_byte = bit.bor(0x80, opcode) -- FIN = 1

  local header
  if len <= 125 then
    header = bits.pack_u8(first_byte) .. bits.pack_u8(len)
  elseif len <= 65535 then
    header = bits.pack_u8(first_byte) .. bits.pack_u8(126) .. bits.pack_be_u16(len)
  else
    header = bits.pack_u8(first_byte) .. bits.pack_u8(127) .. bits.pack_be_u64(len)
  end

  return header .. data
end

--- Decode a WebSocket frame (from client, which is masked)
--- @param data string The raw data
--- @return string? payload, number? opcode, number? consumed
--- consumed is the number of bytes the frame occupies, so the caller can
--- discard exactly that many bytes from the buffer and keep the rest.
function M.decode_frame(data)
  if #data < 2 then
    return nil
  end

  local first_byte = data:byte(1)
  local second_byte = data:byte(2)

  local opcode = bit.band(first_byte, 0x0F)
  local is_masked = bit.band(second_byte, 0x80) ~= 0
  local payload_len = bit.band(second_byte, 0x7F)

  local offset = 2
  if payload_len == 126 then
    if #data < 4 then
      return nil
    end
    payload_len = bits.unpack_be_u16(data, 3)
    offset = 4
  elseif payload_len == 127 then
    if #data < 10 then
      return nil
    end
    payload_len = bits.unpack_be_u64(data, 3)
    offset = 10
  end

  local masking_key = ''
  if is_masked then
    if #data < offset + 4 then
      return nil
    end
    masking_key = data:sub(offset + 1, offset + 4)
    offset = offset + 4
  end

  if #data < offset + payload_len then
    return nil
  end

  local consumed = offset + payload_len

  local payload = data:sub(offset + 1, offset + payload_len)

  if is_masked then
    local unmasked = ''
    for i = 1, #payload do
      local mask_byte = masking_key:byte((i - 1) % 4 + 1)
      unmasked = unmasked .. string.char(bit.bxor(payload:byte(i), mask_byte))
    end
    payload = unmasked
  end

  return payload, opcode, consumed
end

return M
