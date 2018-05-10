local fd = io.open("dump.bin", "w")
local hpack = require "hpack"
local encoding_context = hpack.new(4096)
--local header_block = hpack.encode(encoding_context, {[":method"] = "GET"})
local header_block = hpack.encode(encoding_context, ({[1] = {[":method"] = "GET"},
                                                      [2] = {[":path"] = "/"},
                                                      [3] = {[":scheme"] = "http"},
                                                      [4] = {[":authority"] = "localhost:5000"},
                                                      [5] = {["accept"] = "*/*"},
                                                      [6] = {["user-agent"] = "http2_client"}
                                                     }))
--local header_block = hpack.encode(encoding_context, {[1] = {[":path"] = "/sample/path"}})
fd:write(header_block)
local header_list = hpack.decode(encoding_context, header_block)
for _, header_field in ipairs(header_list) do
  for name, value in pairs(header_field) do
    print(name, value)
  end
end
