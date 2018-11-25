local client = require("http.client")
local headers = require("http.headers")

local connection = client.connect {
  host = "192.168.0.109",
  port = 8080,
  tls = false,
  version = 2
}

local h = headers.new()
h:append(":method", "GET")
h:append(":path", "/100mb.dat")
h:append(":scheme", "http")
h:append(":authority", "192.168.0.109:8080")

local stream, body

for i = 1, 10 do
  stream = connection:new_stream()
  stream:write_headers(h, true)
  stream:get_body_as_string()
end