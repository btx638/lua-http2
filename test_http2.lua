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

local headers = {}
table.insert(headers, h1)
table.insert(headers, h2)
table.insert(headers, h3)

copas.addthread(function()
  local response_headers, s = http2.request("localhost", 8080, nil, h1)

  --for _, h in ipairs(response_headers) do
  --  for name, value in pairs(h) do
  --    print(name, value)
  --  end
  --end

  local fd = io.open("s1", "w")
  local body = s:get_body()
  fd:write(body)
end)

copas.addthread(function()
  local response_headers, s2 = http2.request("localhost", 8080, nil, h2)

  --for _, h in ipairs(response_headers) do
  --  for name, value in pairs(h) do
  --    print(name, value)
  --  end
  --end

  local fd = io.open("s2", "w")
  local body = s2:get_body()
  fd:write(body)
end)

copas.addthread(function()
  local response_headers, s3 = http2.request("localhost", 8080, nil, h3)

  --for _, h in ipairs(response_headers) do
  --  for name, value in pairs(h) do
  --    print(name, value)
  --  end
  --end

  local fd = io.open("s3", "w")
  local body = s3:get_body()
  fd:write(body)
end)

copas.loop()
