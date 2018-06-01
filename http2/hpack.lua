local static_table = {}

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
  local old_entry_size = 24 + #pair
  self.dynamic_table_size = self.dynamic_table_size - old_entry_size
  if self.dynamic_table_size == 0 then
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
  if not static_table[name] then
    self.dynamic_names_to_indexes[name] = tail
    self.dynamic_names_to_indexes[tail] = name
  end
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
    local prefix_mask = 2^prefix - 1
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

local function decode_integer(header_block, prefix, pos)
  pos = pos or 1
  local prefix_mask = 2^prefix - 1
  if pos > #header_block then return end
  local I = prefix_mask & header_block.byte(header_block, pos)
  if I == prefix_mask then
    local M = 0
    repeat
      pos = pos + 1
      if pos > #header_block then return end
      local B = header_block.byte(header_block,pos)
      I = I + (B & 127) * 2^M
      M = M + 7
    until (B & 128) ~= 128
  end
  return I, pos + 1
end

local huffman_decode, huffman_encode
do
  local huffman_codes = {
    [  0] = "1111111111000";
    [  1] = "11111111111111111011000";
    [  2] = "1111111111111111111111100010";
    [  3] = "1111111111111111111111100011";
    [  4] = "1111111111111111111111100100";
    [  5] = "1111111111111111111111100101";
    [  6] = "1111111111111111111111100110";
    [  7] = "1111111111111111111111100111";
    [  8] = "1111111111111111111111101000";
    [  9] = "111111111111111111101010";
    [ 10] = "111111111111111111111111111100";
    [ 11] = "1111111111111111111111101001";
    [ 12] = "1111111111111111111111101010";
    [ 13] = "111111111111111111111111111101";
    [ 14] = "1111111111111111111111101011";
    [ 15] = "1111111111111111111111101100";
    [ 16] = "1111111111111111111111101101";
    [ 17] = "1111111111111111111111101110";
    [ 18] = "1111111111111111111111101111";
    [ 19] = "1111111111111111111111110000";
    [ 20] = "1111111111111111111111110001";
    [ 21] = "1111111111111111111111110010";
    [ 22] = "111111111111111111111111111110";
    [ 23] = "1111111111111111111111110011";
    [ 24] = "1111111111111111111111110100";
    [ 25] = "1111111111111111111111110101";
    [ 26] = "1111111111111111111111110110";
    [ 27] = "1111111111111111111111110111";
    [ 28] = "1111111111111111111111111000";
    [ 29] = "1111111111111111111111111001";
    [ 30] = "1111111111111111111111111010";
    [ 31] = "1111111111111111111111111011";
    [ 32] = "010100";
    [ 33] = "1111111000";
    [ 34] = "1111111001";
    [ 35] = "111111111010";
    [ 36] = "1111111111001";
    [ 37] = "010101";
    [ 38] = "11111000";
    [ 39] = "11111111010";
    [ 40] = "1111111010";
    [ 41] = "1111111011";
    [ 42] = "11111001";
    [ 43] = "11111111011";
    [ 44] = "11111010";
    [ 45] = "010110";
    [ 46] = "010111";
    [ 47] = "011000";
    [ 48] = "00000";
    [ 49] = "00001";
    [ 50] = "00010";
    [ 51] = "011001";
    [ 52] = "011010";
    [ 53] = "011011";
    [ 54] = "011100";
    [ 55] = "011101";
    [ 56] = "011110";
    [ 57] = "011111";
    [ 58] = "1011100";
    [ 59] = "11111011";
    [ 60] = "111111111111100";
    [ 61] = "100000";
    [ 62] = "111111111011";
    [ 63] = "1111111100";
    [ 64] = "1111111111010";
    [ 65] = "100001";
    [ 66] = "1011101";
    [ 67] = "1011110";
    [ 68] = "1011111";
    [ 69] = "1100000";
    [ 70] = "1100001";
    [ 71] = "1100010";
    [ 72] = "1100011";
    [ 73] = "1100100";
    [ 74] = "1100101";
    [ 75] = "1100110";
    [ 76] = "1100111";
    [ 77] = "1101000";
    [ 78] = "1101001";
    [ 79] = "1101010";
    [ 80] = "1101011";
    [ 81] = "1101100";
    [ 82] = "1101101";
    [ 83] = "1101110";
    [ 84] = "1101111";
    [ 85] = "1110000";
    [ 86] = "1110001";
    [ 87] = "1110010";
    [ 88] = "11111100";
    [ 89] = "1110011";
    [ 90] = "11111101";
    [ 91] = "1111111111011";
    [ 92] = "1111111111111110000";
    [ 93] = "1111111111100";
    [ 94] = "11111111111100";
    [ 95] = "100010";
    [ 96] = "111111111111101";
    [ 97] = "00011";
    [ 98] = "100011";
    [ 99] = "00100";
    [100] = "100100";
    [101] = "00101";
    [102] = "100101";
    [103] = "100110";
    [104] = "100111";
    [105] = "00110";
    [106] = "1110100";
    [107] = "1110101";
    [108] = "101000";
    [109] = "101001";
    [110] = "101010";
    [111] = "00111";
    [112] = "101011";
    [113] = "1110110";
    [114] = "101100";
    [115] = "01000";
    [116] = "01001";
    [117] = "101101";
    [118] = "1110111";
    [119] = "1111000";
    [120] = "1111001";
    [121] = "1111010";
    [122] = "1111011";
    [123] = "111111111111110";
    [124] = "11111111100";
    [125] = "11111111111101";
    [126] = "1111111111101";
    [127] = "1111111111111111111111111100";
    [128] = "11111111111111100110";
    [129] = "1111111111111111010010";
    [130] = "11111111111111100111";
    [131] = "11111111111111101000";
    [132] = "1111111111111111010011";
    [133] = "1111111111111111010100";
    [134] = "1111111111111111010101";
    [135] = "11111111111111111011001";
    [136] = "1111111111111111010110";
    [137] = "11111111111111111011010";
    [138] = "11111111111111111011011";
    [139] = "11111111111111111011100";
    [140] = "11111111111111111011101";
    [141] = "11111111111111111011110";
    [142] = "111111111111111111101011";
    [143] = "11111111111111111011111";
    [144] = "111111111111111111101100";
    [145] = "111111111111111111101101";
    [146] = "1111111111111111010111";
    [147] = "11111111111111111100000";
    [148] = "111111111111111111101110";
    [149] = "11111111111111111100001";
    [150] = "11111111111111111100010";
    [151] = "11111111111111111100011";
    [152] = "11111111111111111100100";
    [153] = "111111111111111011100";
    [154] = "1111111111111111011000";
    [155] = "11111111111111111100101";
    [156] = "1111111111111111011001";
    [157] = "11111111111111111100110";
    [158] = "11111111111111111100111";
    [159] = "111111111111111111101111";
    [160] = "1111111111111111011010";
    [161] = "111111111111111011101";
    [162] = "11111111111111101001";
    [163] = "1111111111111111011011";
    [164] = "1111111111111111011100";
    [165] = "11111111111111111101000";
    [166] = "11111111111111111101001";
    [167] = "111111111111111011110";
    [168] = "11111111111111111101010";
    [169] = "1111111111111111011101";
    [170] = "1111111111111111011110";
    [171] = "111111111111111111110000";
    [172] = "111111111111111011111";
    [173] = "1111111111111111011111";
    [174] = "11111111111111111101011";
    [175] = "11111111111111111101100";
    [176] = "111111111111111100000";
    [177] = "111111111111111100001";
    [178] = "1111111111111111100000";
    [179] = "111111111111111100010";
    [180] = "11111111111111111101101";
    [181] = "1111111111111111100001";
    [182] = "11111111111111111101110";
    [183] = "11111111111111111101111";
    [184] = "11111111111111101010";
    [185] = "1111111111111111100010";
    [186] = "1111111111111111100011";
    [187] = "1111111111111111100100";
    [188] = "11111111111111111110000";
    [189] = "1111111111111111100101";
    [190] = "1111111111111111100110";
    [191] = "11111111111111111110001";
    [192] = "11111111111111111111100000";
    [193] = "11111111111111111111100001";
    [194] = "11111111111111101011";
    [195] = "1111111111111110001";
    [196] = "1111111111111111100111";
    [197] = "11111111111111111110010";
    [198] = "1111111111111111101000";
    [199] = "1111111111111111111101100";
    [200] = "11111111111111111111100010";
    [201] = "11111111111111111111100011";
    [202] = "11111111111111111111100100";
    [203] = "111111111111111111111011110";
    [204] = "111111111111111111111011111";
    [205] = "11111111111111111111100101";
    [206] = "111111111111111111110001";
    [207] = "1111111111111111111101101";
    [208] = "1111111111111110010";
    [209] = "111111111111111100011";
    [210] = "11111111111111111111100110";
    [211] = "111111111111111111111100000";
    [212] = "111111111111111111111100001";
    [213] = "11111111111111111111100111";
    [214] = "111111111111111111111100010";
    [215] = "111111111111111111110010";
    [216] = "111111111111111100100";
    [217] = "111111111111111100101";
    [218] = "11111111111111111111101000";
    [219] = "11111111111111111111101001";
    [220] = "1111111111111111111111111101";
    [221] = "111111111111111111111100011";
    [222] = "111111111111111111111100100";
    [223] = "111111111111111111111100101";
    [224] = "11111111111111101100";
    [225] = "111111111111111111110011";
    [226] = "11111111111111101101";
    [227] = "111111111111111100110";
    [228] = "1111111111111111101001";
    [229] = "111111111111111100111";
    [230] = "111111111111111101000";
    [231] = "11111111111111111110011";
    [232] = "1111111111111111101010";
    [233] = "1111111111111111101011";
    [234] = "1111111111111111111101110";
    [235] = "1111111111111111111101111";
    [236] = "111111111111111111110100";
    [237] = "111111111111111111110101";
    [238] = "11111111111111111111101010";
    [239] = "11111111111111111110100";
    [240] = "11111111111111111111101011";
    [241] = "111111111111111111111100110";
    [242] = "11111111111111111111101100";
    [243] = "11111111111111111111101101";
    [244] = "111111111111111111111100111";
    [245] = "111111111111111111111101000";
    [246] = "111111111111111111111101001";
    [247] = "111111111111111111111101010";
    [248] = "111111111111111111111101011";
    [249] = "1111111111111111111111111110";
    [250] = "111111111111111111111101100";
    [251] = "111111111111111111111101101";
    [252] = "111111111111111111111101110";
    [253] = "111111111111111111111101111";
    [254] = "111111111111111111111110000";
    [255] = "11111111111111111111101110";
    EOS   = "111111111111111111111111111111";
  }
  local function bit_string_to_byte(bitstring)
    return string.char(tonumber(bitstring, 2))
  end
  huffman_encode = function(s)
    -- [TODO]: optimize
    local t = { s:byte(1, -1) }
    for i=1, #s do
      t[i] = huffman_codes[t[i]]
    end
    local bitstring = table.concat(t)
    -- round up to next octet
    bitstring = bitstring .. ("1"):rep(7 - (#bitstring - 1) % 8)
    local bytes = bitstring:gsub("........", bit_string_to_byte)
    return bytes
  end
  -- Build tree for huffman decoder
  local huffman_tree = {}
  for k, v in pairs(huffman_codes) do
    local prev_node
    local node = huffman_tree
    local lr
    for j=1, #v do
      lr = v:sub(j, j)
      prev_node = node
      node = prev_node[lr]
      if node == nil then
        node = {}
        prev_node[lr] = node
      end
    end
    prev_node[lr] = k
  end
  local byte_to_bitstring = {}
  for i=0, 255 do
    local val = ""
    for j=7, 0, -1 do
      val = val .. ((i & 2^j) ~= 0 and "1" or "0")
    end
    byte_to_bitstring[string.char(i)] = val
  end
  local EOS_length = #huffman_codes.EOS
  huffman_decode = function(s)
    local bitstring = s:gsub(".", byte_to_bitstring)
    local node = huffman_tree
    local output = {}
    for c in bitstring:gmatch(".") do
      node = node[c]
      local nt = type(node)
      if nt == "number" then
        table.insert(output, node)
        node = huffman_tree
      elseif node == "EOS" then
        -- 5.2: A Huffman encoded string literal containing the EOS symbol MUST be treated as a decoding error.
        -- error: compression
      elseif nt ~= "table" then
        -- error: compression
      end
    end
    --[[ Ensure that any left over bits are all one.
    Section 5.2: A padding not corresponding to the most significant bits
    of the code for the EOS symbol MUST be treated as a decoding error]]
    if node ~= huffman_tree then
      -- We check this by continuing through on the '1' branch and ensure that we end up at EOS
      local n_padding = EOS_length
      while type(node) == "table" do
        node = node["1"]
        n_padding = n_padding - 1
      end
      if node ~= "EOS" then
        -- error: compression
      end
      -- Section 5.2: A padding strictly longer than 7 bits MUST be treated as a decoding error
      if n_padding < 0 or n_padding >= 8 then
        -- error: compression
      end
    end

    return string.char(table.unpack(output))
  end
end

local function index_to_headerfield(self, index)
  if index <= 61 then
    local bin = static_table[index]
    if bin then
      return string.unpack("s4s4", static_table[index])
    end
  else
    local i = 61 + self.dynamic_table_tail - index + 1
    local bin = self.dynamic_table[i]
    if bin then
      return string.unpack("s4s4", bin)
    end
  end
  return
end

local function decode_string(str, pos)
  pos = pos or 1
  if pos > #str then return end
  local first_byte = str.byte(str, pos)
  local huffman = first_byte & 0x80 ~= 0
  local len
  len, pos = decode_integer(str, 7, pos)
  if len == nil then return end
  local newpos = pos + len
  if newpos > #str+1 then return end
  local val = str:sub(pos, newpos - 1)
  if huffman then
    local err
    val, err = huffman_decode(val)
    if not val then
      return nil, err
    end
  end
  return val, newpos
end

local function decode_helper(self, header_block, prefix, pos)
  local index, name, value
  index, pos = decode_integer(header_block, prefix, pos)
  if index == nil then
    return index, pos
  end
  if index == 0 then
    name, pos = decode_string(header_block, pos)
    if name == nil then
      return name, pos
    end
    value, pos = decode_string(header_block, pos)
    if value == nil then
      return value, pos
    end
  else
    name = index_to_headerfield(self, index)
    if name == nil then
      -- error: compression
    end
    value, pos = decode_string(header_block, pos)
    if value == nil then
      return value, pos
    end
  end
  return name, value, pos
end

function resize_dynamic_table(self, new_size)
  assert(new_size >= 0)
  if new_size > self.maxsize then
    -- error: compression
  end
  while new_size < self.dynamic_table_size do
    assert(evict(self))
  end
  self.dynamic_table_maxsize = new_size
  return true
end

local function serialize(self, name, value, huffman)
  local i = string.pack("s4s4", name, value or "")
  -- 6.1. Indexed Header Field Representation
  if static_table[i] then
    return encode_integer(static_table[i], 7, 0x80)
  end
  -- 6.2.1. Literal Header Field with Incremental Indexing - Indexed Name
  if static_table[name] then
    i = static_table[name]
    add_dynamic_table(self, name, value, static_table[i])
    return encode_integer(i, 6, 0x40) .. encode_integer(#value, 7, 0) .. value
  end
  if self.dynamic_names_to_indexes[name] then
    i = 61 + self.dynamic_table_tail - self.dynamic_names_to_indexes[name] + 1
    add_dynamic_table(self, name, value, i)
    return encode_integer(i, 6, 0x40) .. encode_integer(#value, 7, 0) .. value
  end
  -- 6.2.1. Literal Header Field with Incremental Indexing - New Name
  add_dynamic_table(self, name, value, i)
  return "\64" .. encode_integer(#name, 7, 0) .. name .. encode_integer(#value, 7, 0) .. value
  -- 6.2.2. Literal Header Field without Indexing?
  -- 6.2.3. Literal Header Field Never Indexed?
end

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

local function encode(self, header_list)
  local header_block = {}
  for _, header_field in ipairs(header_list) do
    for name, value in pairs(header_field) do
      table.insert(header_block, serialize(self, name, value, huffman))
    end
  end
  return table.concat(header_block)
end

local function decode(self, header_block)
  local block_pos = 1
  local header_list = {}
  while block_pos <= #header_block do
    local current_byte = header_block.byte(header_block, block_pos)
    -- 6.1. Indexed Header Field Representation
    if current_byte & 0x80 ~= 0 then
      local index, block_newpos = decode_integer(header_block, 7, block_pos)
      block_pos = block_newpos
      local name, value = index_to_headerfield(self, index)
      if not name then
        -- error: compression
      end
      header_list[#header_list + 1] = {}
      header_list[#header_list][name] = value
    -- 6.2.1. Literal Header Field with Incremental Indexing
    elseif current_byte & 0x40 ~= 0 then
      local name, value, block_newpos = decode_helper(self, header_block, 6, block_pos)
      if not name then
        if not value then
          break
        end
        return nil, value
      end
      block_pos = block_newpos
      add_dynamic_table(self, name, value, string.pack("s4s4", name, value))
      header_list[#header_list + 1] = {}
      header_list[#header_list][name] = value
    -- 6.3. Dynamic Table Size Update
    elseif current_byte & 0x20 ~= 0 then
      if #header_list > 0 then
        -- error: compression
      end
      local size, block_newpos = decode_integer(header_block, 5, block_pos)
      if not size then break end
      block_pos = block_newpos
      local ok, err = resize_dynamic_table(self, size)
    -- 6.2.2. Literal Header Field Without Indexing
    else
      local name, value, block_newpos = decode_helper(self, header_block, 4, block_pos)
      if not name then
        if not value then
          break
        end
        return nil, value
      end
      block_pos = block_newpos
      header_list[#header_list + 1] = {}
      header_list[#header_list][name] = value
    end
  end
  return header_list
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
  encode = encode,
  decode = decode
}

return hpack
