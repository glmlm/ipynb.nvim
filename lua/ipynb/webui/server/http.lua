local uv = vim.uv
local M = {}

local status_text = {
  [200] = 'OK',
  [404] = 'Not Found',
  [405] = 'Method Not Allowed',
  [500] = 'Internal Server Error',
}

function M.create_response(status, content_type, body)
  return table.concat({
    'HTTP/1.1 ' .. status .. ' ' .. status_text[status],
    'Content-Type: ' .. content_type,
    'Content-Length: ' .. #body,
    'Connection: close',
    '',
    body,
  }, '\r\n')
end

local mime_types = {
  html = 'text/html',
  js = 'application/javascript',
  css = 'text/css',
  png = 'image/png',
  jpg = 'image/jpeg',
  json = 'application/json',
}

function M.handle_request(data, static_dir)
  local method, path = data:match('^(%w+)%s+([^%s?]+)')
  if not method or not path then
    return nil
  end
  if method ~= 'GET' then
    return M.create_response(405, 'text/plain', 'Method Not Allowed')
  end

  -- Reject any path segment that is '..', so the request can never escape
  -- static_dir via '..' traversal.
  for seg in path:gmatch('/([^/]+)') do
    if seg == '..' then
      return M.create_response(404, 'text/plain', 'Not Found')
    end
  end

  local file_path = path == '/' and '/index.html' or path

  local full_path = static_dir .. file_path
  local fd = uv.fs_open(full_path, 'r', 438)
  if not fd then
    return M.create_response(404, 'text/plain', 'Not Found')
  end

  local stat = uv.fs_fstat(fd)
  local body = uv.fs_read(fd, stat.size, 0)
  uv.fs_close(fd)

  local ext = file_path:match('%.([^.]+)$')
  local content_type = mime_types[ext] or 'text/plain'

  return M.create_response(200, content_type, body)
end

return M
