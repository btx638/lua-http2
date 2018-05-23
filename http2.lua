local connection = require "connection"
local stream = require "stream"
local hpack = require "hpack"

-- Send a HEADERS frame with the requested header list
-- Returns the newly created stream and the response header list
local function submit_request(conn, headers, body)
  local s = stream.new(conn)
  s.id = conn.max_stream_id + 2
  conn.max_stream_id = s.id
  conn.streams[s.id] = s

  --print("# REQUEST\n\n## HEADERS")
  --for _, header_field in ipairs(headers) do
  --  for name, value in pairs(header_field) do
  --    print(name, value)
  --  end
  --end

  -- Request header list
  local header_block = hpack.encode(conn.hpack_context, headers)

  --print("\n## BODY")
  if body then
    -- TODO: correctness: may require padding to fit in a frame
    conn.send_frame(conn, 0x1, 0x4, s.id, header_block)
    local fsize = conn.server_settings.MAX_FRAME_SIZE
    for i = 1, #body, fsize do
      if i + fsize >= #body then
        conn.send_frame(conn, 0x0, 0x1, s.id, string.sub(body, i))
      else
        conn.send_frame(conn, 0x0, 0x0, s.id, string.sub(body, i, i + fsize - 1))
      end
    end
  else
    conn.send_frame(conn, 0x1, 0x4 | 0x1, s.id, header_block)
  end

  local header_list = stream.get_headers(s)

  --print("\n\n# RESPONSE\n\n## HEADERS")
  --for _, header_field in ipairs(header_list) do
  --  for name, value in pairs(header_field) do
  --    print(name, value)
  --  end
  --end

  return header_list, s
end

local function get_server_settings(conn)
  local server_settings = {}
  local s = conn.streams[0]
  local _, flags, _, settings_payload = conn.recv_frame(conn)
  local parser = stream.frame_parser[0x4]
  local server_settings = parser(s, flags, settings_payload)
  -- Acknowledging the server settings
  conn.send_frame(conn, 0x4, 0x1, 0, "")
  return server_settings
end

local function request(uri, body)
  -- TODO: parse the URI
  local conn = connection.new(uri)
  conn.server_settings = get_server_settings(conn)
  -- Sends an WINDOW_UPDATE frame on the conn level
  conn.send_frame(conn, 0x8, 0x0, 0, string.pack(">I4", "1073741823"))
  local request_headers
  if not body then
    request_headers = {[1] = {[":method"] = "GET"},
                       [2] = {[":path"] = "/"},
                       [3] = {[":scheme"] = "http"},
                       [4] = {[":authority"] = "localhost:8080"},
                      }
  else
    request_headers = {[1] = {[":method"] = "POST"},
                       [2] = {[":path"] = "/"},
                       [3] = {[":scheme"] = "http"},
                       [4] = {[":authority"] = "localhost:8080"},
                      }
  end
  -- Performs the request
  local response_headers, s = submit_request(conn, request_headers, body)
  -- Sends an WINDOW_UPDATE frame on the stream level
  conn.send_frame(conn, 0x8, 0x0, s.id, string.pack(">I4", "1073741823"))
  -- DATA frame containing the message payload
  local payload = stream.get_message_data(s)
  io.write(payload)
end

local http2 = {
  request = request
}

return http2
