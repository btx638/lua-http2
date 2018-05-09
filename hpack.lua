local static_table = {}
local dynamic_table = {}
local fd = io.open("dump.bin", "w")

local function new(HEADER_TABLE_SIZE)
  local self = {
    dynamic_table = {},
    dynamic_table_size = 0,
    maxsize = HEADER_TABLE_SIZE or 0,
    dynamic_table_maxsize = nil,
    dynamic_table_head = 1,
    dynamic_table_tail = 0,
    dynamic_names_to_indexes = {}
  }
  self.dynamic_table_maxsize = self.maxsize
  return self
end

local function evict(self)
  local old_head = self.dynamic_table_head
  if old_head > self.dynamic_table_tail then return false end -- can it happen?
  local pair = self.dynamic_table[old_head]
  if self.dynamic_table[pair] == old_head then -- don't want to evict a duplicate entry (2.3.2)
    self.dynamic_table[pair] = nil
  end
  self.dynamic_table[old_head] = nil
  local name = self.dynamic_names_to_indexes[old_head]
  if name ~= nil then
    if self.dynamic_names_to_indexes[name] == old_head then
      self.dynamic_names_to_indexes[name] = nil
    end
    self.dynamic_names_to_indexes[old_head] = nil
  end
  local old_entry_size = dynamic_table_entry_size(pair)
  self.dynamic_table_size = self.dynamic_table_size - old_entry_size
  if self.dynamic_table_size == 0 then
    -- [Premature Optimisation]: reset to head at 1 and tail at 0
    self.dynamic_table_head = 1
    self.dynamic_table_tail = 0
  else
    self.dynamic_table_head = old_head + 1
  end
  return true
end


local function add_dynamic_table(self, name, value, bin)
  local new_entry_size = 24 + #bin
  -- 4.4. Entry Eviction When Adding New Entries
  while self.dynamic_table_size > self.dynamic_table_maxsize - new_entry_size do
    if not evict(self) then return end
  end
  local tail = self.dynamic_table_tail + 1
  self.dynamic_table_tail = tail
  self.dynamic_table[bin] = tail
  self.dynamic_table[tail] = bin
  self.dynamic_names_to_indexes[name] = tail
  self.dynamic_names_to_indexes[tail] = name
  self.dynamic_table_size = self.dynamic_table_size + new_entry_size
end

local function add_static_table(i, name, value)
  local header_field = string.pack("s4s4", name, value or "")
  static_table[header_field] = i
  static_table[i] = header_field
  static_table[name] = i
end

local function encode_integer(i, prefix, mask)
  assert(prefix >= 0 and prefix <= 8 and prefix % 1 == 0)
  assert(mask >= 0 and mask <= 256 and mask % 1 == 0)
  if i < 2^prefix then
    return string.char(mask | i)
  else
    local prefix_mask = 2^prefix-1
    local chars = {
      prefix_mask | mask;
    }
    local j = 2
    i = i - prefix_mask
    while i >= 128 do
      chars[j] = i % 128 + 128
      j = j + 1
      i = math.floor(i / 128)
    end
    chars[j] = i
    return string.char(table.unpack(chars, 1, j))
  end
end

local function add(self, name, value, huffman)
  local i = string.pack("s4s4", name, value or "")
  -- 6.1. Indexed Header Field Representation
  if static_table[i] then
    return encode_integer(static_table[i], 7, 0x80)
  end
  -- 6.2.1. Literal Header Field with Incremental Indexing - Indexed Name
  if static_table[name] then
    i = static_table[name]
    return encode_integer(i, 6, 0x40) .. encode_integer(#value, 7, 0) .. value
  end
  if self.dynamic_names_to_indexes[name] then
    i = 61 + self.dynamic_table_tail - self.dynamic_names_to_indexes + 1
    add_dynamic_table(self, name, value, i)
    return encode_integer(i, 6, 0x40) .. encode_integer(#value, 7, 0) .. value
  end
  -- 6.2.1. Literal Header Field with Incremental Indexing - New Name
  add_dynamic_table(self, name, value, i)
  return "\64" .. encode_integer(#name, 7, 0) .. name .. encode_integer(#value, 7, 0) .. value
  -- 6.2.2. Literal Header Field without Indexing?
  -- 6.2.3. Literal Header Field Never Indexed?
end

local function serialize(self, header_list)
  local header_block = {}
  for name, value in pairs(header_list) do
    table.insert(header_block, add(self, name, value, huffman))
  end
  return header_block
end

local function decode(fragment)
end

add_static_table( 1, ":authority")
add_static_table( 2, ":method", "GET")
add_static_table( 3, ":method", "POST")
add_static_table( 4, ":path", "/")
add_static_table( 5, ":path", "/index.html")
add_static_table( 6, ":scheme", "http")
add_static_table( 7, ":scheme", "https")
add_static_table( 8, ":status", "200")
add_static_table( 9, ":status", "204")
add_static_table(10, ":status", "206")
add_static_table(11, ":status", "304")
add_static_table(12, ":status", "400")
add_static_table(13, ":status", "404")
add_static_table(14, ":status", "500")
add_static_table(15, "accept-charset")
add_static_table(16, "accept-encoding", "gzip, deflate")
add_static_table(17, "accept-language")
add_static_table(18, "accept-ranges")
add_static_table(19, "accept")
add_static_table(20, "access-control-allow-origin")
add_static_table(21, "age")
add_static_table(22, "allow")
add_static_table(23, "authorization")
add_static_table(24, "cache-control")
add_static_table(25, "content-disposition")
add_static_table(26, "content-encoding")
add_static_table(27, "content-language")
add_static_table(28, "content-length")
add_static_table(29, "content-location")
add_static_table(30, "content-range")
add_static_table(31, "content-type")
add_static_table(32, "cookie")
add_static_table(33, "date")
add_static_table(34, "etag")
add_static_table(35, "expect")
add_static_table(36, "expires")
add_static_table(37, "from")
add_static_table(38, "host")
add_static_table(39, "if-match")
add_static_table(40, "if-modified-since")
add_static_table(41, "if-none-match")
add_static_table(42, "if-range")
add_static_table(43, "if-unmodified-since")
add_static_table(44, "last-modified")
add_static_table(45, "link")
add_static_table(46, "location")
add_static_table(47, "max-forwards")
add_static_table(48, "proxy-authenticate")
add_static_table(49, "proxy-authorization")
add_static_table(50, "range")
add_static_table(51, "referer")
add_static_table(52, "refresh")
add_static_table(53, "retry-after")
add_static_table(54, "server")
add_static_table(55, "set-cookie")
add_static_table(56, "strict-transport-security")
add_static_table(57, "transfer-encoding")
add_static_table(58, "user-agent")
add_static_table(59, "vary")
add_static_table(60, "via")
add_static_table(61, "www-authenticate")

local hpack = {
  new = new,
  encode = serialize,
  decode = decode
}

return hpack
