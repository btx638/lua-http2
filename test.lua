local connection = require "connection"
local stream = require "stream"
local hpack = require "hpack"
local copas = require "copas"

local function protocol(host)
  local c = connection.new(host)
end

copas.addthread(protocol, "localhost")
copas.loop()
