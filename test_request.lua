local http2 = require "http2"
local copas = require "copas"

local fd = io.open("request_out", "w")
local response_headers, s = http2.request("http://localhost:8080/")
local body = s:get_body()

for _, header in ipairs(response_headers) do
  for name, value in pairs(header) do
    print(name, value)
  end
end

fd:write(body)
