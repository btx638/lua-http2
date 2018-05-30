local connection = require "connection"
local stream = require "stream"
local hpack = require "hpack"
local socket = require "socket"
local copas = require "copas"

local function request(host, port, body, request_headers)
  if headers == nil then
    headers = {}
    table.insert(headers, {[":method"] = "GET"})
    table.insert(headers, {[":path"] = "/"})
    table.insert(headers, {[":scheme"] = "http"})
    table.insert(headers, {[":authority"] = "localhost:8080"})
  end
  local client = socket.tcp()
  client:connect(host, port)
  local conn = connection.new(client)
  local stream0 = conn.streams[0]
  stream0:send_window_update("1073741823")
  local s = stream.new(conn)
  s.id = conn.max_stream_id + 2
  conn.max_stream_id = s.id
  conn.streams[s.id] = s
  s:send_headers(request_headers, body)
  s:send_window_update("1073741823")
  local response_headers = s:get_headers()
  return response_headers, s
end

local http2 = {
  request = request
}

return http2
