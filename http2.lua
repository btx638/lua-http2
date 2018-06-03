local connection = require "http2.connection"
local stream = require "http2.stream"
local hpack = require "http2.hpack"
local url = require "socket.url"

local function request(uri, body, headers)
  local parsed_uri = url.parse(uri)
  if headers == nil then
    headers = {}
    table.insert(headers, {[":method"] = "GET"})
    table.insert(headers, {[":path"] = parsed_uri.path})
    table.insert(headers, {[":scheme"] = parsed_uri.scheme})
    table.insert(headers, {[":authority"] = parsed_uri.authority})
  end
  local conn = connection.new(parsed_uri.host, parsed_uri.port)
  local stream0 = conn.streams[0]
  stream0:encode_window_update("1073741823")
  local s = stream.new(conn)
  s:set_headers(headers, body == nil)
  if body then s:set_body() end
  s:encode_window_update("1073741823")
  local response_headers = s:get_headers()
  return response_headers, s
end

local http2 = {
  request = request
}

return http2
