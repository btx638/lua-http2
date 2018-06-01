local http2 = require "http2"
local copas = require "copas"

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

local fd = assert(io.open("fuck", "w"))
local response_headers, s = http2.request("localhost", 8080, nil, h1)
local body = s:get_body()

for _, header in ipairs(response_headers) do
  for name, value in pairs(header) do
    print(name, value)
  end
end

fd:write(body)
