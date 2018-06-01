local connection = require "http2.connection"
local stream = require "http2.stream"
local hpack = require "http2.hpack"

local function request(host, port, body, headers)
  if headers == nil then
    headers = {}
    fields = {}
    table.insert(fields, {[":method"] = "GET"})
    table.insert(fields, {[":path"] = "/"})
    table.insert(fields, {[":scheme"] = "http"})
    table.insert(fields, {[":authority"] = "localhost:8080"})
    table.insert(headers, fields)
  end
  local conn = connection.new(host, port)
  local stream0 = conn.streams[0]
  stream0:send_window_update("1073741823")
  local s = stream.new(conn)
  s:send_headers(headers, body)
  s:send_window_update("1073741823")
  local response_headers = s:get_headers()
  return response_headers, s
end

local http2 = {
  request = request
}

return http2
