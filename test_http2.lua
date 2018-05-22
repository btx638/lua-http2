local http2 = require "http2"
local copas = require "copas"

local function handler(uri)
  http2.request(uri)
end

copas.addthread(handler, "localhost")
copas.loop()
