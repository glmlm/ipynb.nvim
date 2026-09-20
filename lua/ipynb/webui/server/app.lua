local uv = vim.uv
local M = {}
local http = require('ipynb.webui.server.http')
local ws = require('ipynb.webui.server.websocket')

local App = {}
App.__index = App

function M.create_app(opts)
  local obj = {
    port = opts.port or 8080,
    static_dir = opts.static_dir,
    server = nil,
    clients = {},
  }
  setmetatable(obj, App)
  return obj
end

function App:start()
  self.server = uv.new_tcp()
  self.server:bind('127.0.0.1', self.port)
  self.server:listen(128, function(err)
    if err then
      print('Server error: ' .. err)
      return
    end

    local client = uv.new_tcp()
    self.server:accept(client)

    local buffer = ''
    client:read_start(function(err, data)
      if err then
        self:close_client(client)
        return
      end

      if data then
        buffer = buffer .. data

        -- Check if this is already a WebSocket client
        if self:is_ws_client(client) then
          -- Decode WebSocket frame(s); consume only the bytes the frame used so
          -- frames still waiting in the buffer are processed next.
          local payload, opcode, consumed = ws.decode_frame(buffer)
          if payload then
            buffer = buffer:sub(consumed + 1)

            -- Handle ping/pong frames
            if opcode == 0x09 then  -- Ping
              local pong = ws.encode_frame(payload, 0x0A)
              client:write(pong)
            -- Handle text frames (client messages)
            elseif opcode == 0x01 then
              -- Handle client message if callback is registered
              if self.on_message then
                self.on_message(payload)
              end
            end
          end
          return
        end

        -- Check for WebSocket upgrade request
        if ws.is_upgrade_request(buffer) then
          local resp = ws.create_handshake_response(buffer)
          if resp then
            client:write(resp)
            self:add_client(client)
            buffer = ''
          end
          return
        end

        -- Handle HTTP requests (static files)
        local resp = http.handle_request(buffer, self.static_dir)
        client:read_stop()
        if resp then
          client:write(resp, function()
            client:close()
          end)
        else
          client:close()
        end
        buffer = ''
      else
        self:close_client(client)
      end
    end)
  end)

  print('Internal server started on http://127.0.0.1:' .. self.port)
end

function App:add_client(client)
  table.insert(self.clients, client)

  -- Trigger sync_notebook to send data via WebSocket
  vim.schedule(function()
    local sync_mod = require('ipynb.webui.sync')
    sync_mod.sync_notebook()
    sync_mod.sync_cursor()
  end)
end

function App:close_client(client)
  client:read_stop()
  client:close()
  self:remove_client(client)
end

function App:remove_client(client)
  for i, c in ipairs(self.clients) do
    if c == client then
      table.remove(self.clients, i)
      break
    end
  end
end

function App:is_ws_client(client)
  for _, c in ipairs(self.clients) do
    if c == client then
      return true
    end
  end
  return false
end

function App:broadcast(data)
  local frame = ws.encode_frame(data)
  for _, client in ipairs(self.clients) do
    if not client:is_closing() then
      client:write(frame)
    end
  end
end

function App:stop()
  if self.server then
    self.server:close()
  end
  for _, client in ipairs(self.clients) do
    client:read_stop()
    client:close()
  end
  self.clients = {}
end

return M
