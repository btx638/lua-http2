local socket = require("socket")
local copas = require("copas")

local server = socket.bind("localhost", 6642)

local function handler(s)
  while true do
    local data = copas.receive(s, 5)
    copas.send(s, data)
  end
end

copas.addserver(server, handler)
copas.loop()