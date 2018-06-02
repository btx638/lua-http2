local connection = require "http2.connection"
local stream = require "http2.stream"

local h1 = {}
table.insert(h1, {[":method"] = "GET"})
table.insert(h1, {[":path"] = "/"})
table.insert(h1, {[":scheme"] = "http"})
table.insert(h1, {[":authority"] = "localhost:8080"})
local h2 = {}
table.insert(h2, {[":method"] = "GET"})
table.insert(h2, {[":path"] = "/index2.html"})
table.insert(h2, {[":scheme"] = "http"})
table.insert(h2, {[":authority"] = "localhost:8080"})
local h3 = {}
table.insert(h3, {[":method"] = "GET"})
table.insert(h3, {[":path"] = "/index3.html"})
table.insert(h3, {[":scheme"] = "http"})
table.insert(h3, {[":authority"] = "localhost:8080"})

local conn = connection.new("localhost", 8080)
local stream0 = conn.streams[0]
stream0:encode_window_update("1073741823")

local s1 = stream.new(conn)
local s2 = stream.new(conn)
local s3 = stream.new(conn)

s1:encode_headers(h1, nil)
s1:encode_window_update("1073741823")
s2:encode_headers(h2, nil)
s2:encode_window_update("1073741823")
s3:encode_headers(h3, nil)
s3:encode_window_update("1073741823")

local response_headers1 = s1:get_headers()
local response_headers2 = s2:get_headers()
local response_headers3 = s3:get_headers()

for _, header in ipairs(response_headers1) do
  for name, value in pairs(header) do
    print(name, value)
  end
end
print()
for _, header in ipairs(response_headers2) do
  for name, value in pairs(header) do
    print(name, value)
  end
end
print()
for _, header in ipairs(response_headers3) do
  for name, value in pairs(header) do
    print(name, value)
  end
end

local fd1 = assert(io.open("http2_out1", "w"))
local fd2 = assert(io.open("http2_out2", "w"))
local fd3 = assert(io.open("http2_out3", "w"))
local body1 = s1:get_body()
fd1:write(body1)
local body2 = s2:get_body()
fd2:write(body2)
local body3 = s3:get_body()
fd3:write(body3)
