local http2 = require "http2"

local headers = {{[1] = {[":method"] = "GET"},
                  [2] = {[":path"] = "/"},
                  [3] = {[":scheme"] = "http"},
                  [4] = {[":authority"] = "localhost:8080"},
                 },
                 {[1] = {[":method"] = "GET"},
                  [2] = {[":path"] = "/index2.html"},
                  [3] = {[":scheme"] = "http"},
                  [4] = {[":authority"] = "localhost:8080"},
                 },
                 {[1] = {[":method"] = "GET"},
                  [2] = {[":path"] = "/index3.html"},
                  [3] = {[":scheme"] = "http"},
                  [4] = {[":authority"] = "localhost:8080"},
                }}

local body = http2.request("localhost", 8080, nil, headers)
