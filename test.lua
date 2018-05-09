local fd = io.open("dump.bin", "w")
local hpack = require "hpack"
local encoding_context = hpack.new(4096)
--local header_block = hpack.encode(encoding_context, {[":method"] = "GET"})
local header_block = hpack.encode(encoding_context, {["custom-key"] = "custom-header"})
for k, v in pairs(header_block) do fd:write(v) end
--local header_list = hpack.decode(header_block)
--for k, v in pairs(header_list) do print(k, v) end
