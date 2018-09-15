local socket = require("socket")
local copas = require("copas")

local client = socket.connect("localhost", 6642)

copas.addthread(function()
  copas.sleep()
  print("===== thread 1 ======")
  local err, msg = copas.send(client, "data1")
  local res = copas.receive(client, 5)
  print(res)
  print("=====================\n")
end)

copas.addthread(function()
  copas.sleep()
  print("===== thread 2 ======")
  local err, msg = copas.send(client, "data2")
  local res = copas.receive(client, 5)
  print(res)
  print("======================")
end)

copas.loop()