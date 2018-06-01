local http2 = require "http2"
local copas = require "copas"

local headers = {}
table.insert(headers, {[":method"] = "POST"})
table.insert(headers, {[":path"] = "/resource"})
table.insert(headers, {[":scheme"] = "http"})
table.insert(headers, {[":authority"] = "localhost:8080"})

local fd = io.open("request_out", "w")
local response_headers, s = http2.request("http://localhost:8080/resource", "f", headers)
local body = s:get_body()

for _, header in ipairs(response_headers) do
  for name, value in pairs(header) do
    print(name, value)
  end
end

fd:write(body)
