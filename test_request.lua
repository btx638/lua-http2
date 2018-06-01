local http2 = require "http2"
local copas = require "copas"

local headers = {}
table.insert(headers, {[":method"] = "GET"})
table.insert(headers, {[":path"] = "/"})
table.insert(headers, {[":scheme"] = "http"})
table.insert(headers, {[":authority"] = "localhost:8080"})

local fd = assert(io.open("request_out", "w"))
local response_headers, s = http2.request("localhost", 8080, nil, headers)
local body = s:get_body()

for _, header in ipairs(response_headers) do
  for name, value in pairs(header) do
    print(name, value)
  end
end

fd:write(body)
