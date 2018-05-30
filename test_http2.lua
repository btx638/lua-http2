local http2 = require "http2"

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

local b1, b2, b3 = http2.request("localhost", 8080, nil, headers)
