local connection = require "http2.connection"
local stream = require "http2.stream"

local fd = assert(io.open("http2_out", "w"))

local h1 = {}
table.insert(h1, {[":method"] = "GET"})
table.insert(h1, {[":path"] = "/"})
table.insert(h1, {[":scheme"] = "http"})
table.insert(h1, {[":authority"] = "localhost:8080"})

local conn = connection.new("localhost", 8080)
local stream0 = conn.streams[0]
stream0:send_window_update("1073741823")
local s = stream.new(conn)
s:send_headers(h1, body)
s:send_window_update("1073741823")
local response_headers = s:get_headers()
local body = s:get_body()

for _, header in ipairs(response_headers) do
  for name, value in pairs(header) do
    print(name, value)
  end
end

fd:write(body)
