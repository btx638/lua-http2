local http2 = require "http2"

local headers = {}
table.insert(headers, {[":method"] = "GET"})
table.insert(headers, {[":path"] = "/"})
table.insert(headers, {[":scheme"] = "http"})
table.insert(headers, {[":authority"] = "localhost:8080"})

local response_headers, stream = http2.request("localhost", 8080, nil, headers)
local body = stream:get_body()
io.write(body)
