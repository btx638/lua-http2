local hpack = require "http2.hpack"
local stream = require "http2.stream"
local socket = require "socket"
local copas = require "copas"

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

-- Settings indexed both as names and as hexadecimal identifiers
for id = 0x1, 0x6 do
  settings_parameters[settings_parameters[id]] = id
  default_settings[id] = default_settings[settings_parameters[id]]
end

local mt = {__index = {}}

function mt.__index:send_frame(ftype, flags, stream_id, payload)
  local header = string.pack(">I3BBI4", #payload, ftype, flags, stream_id)
  self.client:send(header)
  self.client:send(payload)
end

local function getframe(conn)
  local header, payload, err
  local length, ftype, flags, stream_id
  header, err, partial = conn.client:receive(9)
  if err then return nil, err end
  length, ftype, flags, stream_id = string.unpack(">I3BBI4", header)
  payload, err = conn.client:receive(length)
  if err then return nil, err end
  stream_id = stream_id & 0x7fffffff
  return {
    ftype = ftype,
    flags = flags,
    stream_id = stream_id,
    payload = payload
  }
end

local function initiate_connection(conn)
  conn.client:send("PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n")
  local s = stream.new(conn, 0)
  s:encode_settings(false)
    -- The first frame sent by the server MUST consist of a SETTINGS frame
  local frame, err = getfirstframe(conn)
  s:parse_frame(frame.ftype, frame.flags, frame.payload)
  -- The SETTINGS frames received from a peer as part of the connection preface
  -- MUST be acknowledged after sending the connection preface
  s:encode_settings(true)
  local server_table_size = conn.server_settings.HEADER_TABLE_SIZE
  local default_table_size = default_settings.HEADER_TABLE_SIZE
  conn.hpack_context = hpack.new(server_table_size or default_table_size)
end

local function dispatch(conn)
  while true do
    local req = table.remove(conn.pending, 1)
    if not req then
      copas.sleep(-1)
    else
      if conn.first_frame == false then
        initiate_connection(conn)
        conn.first_frame = true
      else
        local s = conn.streams[req.stream_id]
        if s == nil then s = stream.new(conn, req.stream_id) end
        s:parse_frame(req.ftype, req.flags, req.payload)
      end
    end
  end
end

local function receiver(conn)
  local frame, err, s
  while true do
    frame, err = getframe(conn)
    if err then print("err: ", err) end
    table.insert(conn.pending, frame)
    copas.wakeup(conn.dispatch)
    copas.sleep(0)
  end
end

local function new(host, port)
  local connection = setmetatable({
    client = nil,
    first_frame = false,
    pending = {},
    max_client_streamid = 3,
    max_server_streamid = 0,
    hpack_context = nil,
    server_settings = {},
    streams = {},
    settings_parameters = settings_parameters,
    default_settings = default_settings,
    window = 65535,
    last_stream_id = 0,
    header_block_fragment = nil
  }, mt)
  connection.client = copas.wrap(socket.tcp())
  connection.client:connect(host, port)

  copas.addthread(function()
    copas.sleep(0)

    connection.dispatch = copas.addthread(function()
      copas.sleep(0)
      dispatch(connection)
    end)

    connection.receiver = copas.addthread(function()
      copas.sleep(0)
      receiver(connection)
    end)
  end)
  return connection
end

local connection = {
  new = new
}

return connection
