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

local response_headers, s = http2.request("localhost", 8080, nil, h1)
local fd = assert(io.open("s1", "w"))
local body = s:get_body()
fd:write(body)
