local http2 = require "http2"

local headers = {}
table.insert(headers, {[":method"] = "GET"})
table.insert(headers, {[":path"] = "/"})
table.insert(headers, {[":scheme"] = "http"})
table.insert(headers, {[":authority"] = "localhost:8080"})

local response_headers, stream = http2.request("localhost", 8080, nil, headers)

for _, h in ipairs(response_headers) do
  for name, value in pairs(h) do
    print(name, value)
  end
end

local body = stream:get_body()
