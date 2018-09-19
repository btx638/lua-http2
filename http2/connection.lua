local mt = {__index = {}}

local settings_parameters = {
  [0x1] = "HEADER_TABLE_SIZE",
  [0x2] = "ENABLE_PUSH",
  [0x3] = "MAX_CONCURRENT_STREAMS",
  [0x4] = "INITIAL_WINDOW_SIZE",
  [0x5] = "MAX_FRAME_SIZE",
  [0x6] = "MAX_HEADER_LIST_SIZE"
}

local default_settings = {
  HEADER_TABLE_SIZE      = 4096,
  ENABLE_PUSH            = 0,
  MAX_CONCURRENT_STREAMS = 100,
  INITIAL_WINDOW_SIZE    = 65535,
  MAX_FRAME_SIZE         = 16384,
  MAX_HEADER_LIST_SIZE   = 25600
}

local tls = {
  mode = "client",
  protocol = "any",
  options = {"all", "no_sslv2", "no_sslv3"},
  verify = "none",
  alpn = "h2"
}

-- Settings indexed both as names and as hexadecimal identifiers
for id = 0x1, 0x6 do
  settings_parameters[settings_parameters[id]] = id
  default_settings[id] = default_settings[settings_parameters[id]]
end

function mt.__index:send_frame(ftype, flags, stream_id, payload)
  local header = string.pack(">I3BBI4", #payload, ftype, flags, stream_id)
  self.client:send(header)
  self.client:send(payload)
end

local function new(parsed_url)
  local connection = setmetatable({
    responses = {},
    data = {},
    client = nil,
    tls = tls,
    url = parsed_url,
    recv_server_preface = false,
    stream_finished = nil,
    max_client_streamid = 1,
    max_server_streamid = 2,
    hpack_context = nil,
    server_settings = {},
    streams = {},
    requests = 0,
    settings_parameters = settings_parameters,
    default_settings = default_settings,
    window = 65535,
    last_stream_id_server = 0,
    header_block_fragment = nil
  }, mt)

  return connection
end

local connection = {
  new = new
}

return connection