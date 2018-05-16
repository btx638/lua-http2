local frame_parser = {}

-- DATA frame parser
frame_parser[0x0] = function(stream_id, flags, payload)
end

-- HEADER frame parser
frame_parser[0x1] = function(stream_id, flags, payload)
end

-- PRIORITY frame parser
frame_parser[0x2] = function(stream_id, flags, payload)
end

-- RST_STREAM frame parser
frame_parser[0x3] = function(stream_id, flags, payload)
end

-- SETTING frame parser
frame_parser[0x4] = function(stream_id, flags, payload)
end

-- PUSH_PROMISE frame parser
frame_parser[0x5] = function(stream_id, flags, payload)
end

-- PING frame parser
frame_parser[0x6] = function(stream_id, flags, payload)
end

-- GOAWAY frame parser
frame_parser[0x7] = function(stream_id, flags, payload)
end

-- WINDOW_UPDATE frame parser
frame_parser[0x8] = function(stream_id, flags, payload)
end

-- CONTINUATION frame parser
frame_parser[0x9] = function(stream_id, flags, payload)
end

local stream = {
}

return stream
