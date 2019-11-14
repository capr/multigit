
-- Composable streams for string and cdata-buffer-based I/O.
-- Written by Cosmin Apreutesei. Public Domain.

if not ... then require'stream_test'; return end

local ffi = require'ffi'
local glue = require'glue'

local stream = {}

local const_char_ptr_t = ffi.typeof'const char*'

--allow a function's `buf, sz` args to be `s, [len]`.
local function stringdata(buf, sz)
	if type(buf) == 'string' then
		if sz then
			assert(sz <= #buf, 'string too short')
		else
			sz = #buf
		end
		return ffi.cast(const_char_ptr_t, buf), sz
	else
		return buf, sz
	end
end

--make a `read(sz) -> buf, sz` that is reading from a string or cdata buffer.
function stream.mem_reader(buf, len)
	local buf, len = stringdata(buf, len)
	local i = 0
	return function(n)
		assert(n > 0)
		if i == len then
			return nil, 'eof'
		else
			n = math.min(n, len - i)
			i = i + n
			return buf + i - n, n
		end
	end
end

--convert `read(buf, sz) -> sz` into `read(sz) -> buf, sz` with read-ahead.
function stream.buffer_reader(bufsize, read)
	local buf, sz = glue.gcmalloc(bufsize)
	local i, len, err = 0, 0
	return function(n)
		if len == 0 then
			i = 0
			len, err = read(buf, sz)
			if not len then return nil, err end
		end
		n = math.min(n, len)
		i = i + n
		len = len - n
		return buf + i - n, n
	end
end

--convert `read(sz) -> buf, sz` into `read(buf, sz) -> sz`.
function stream.ownbuffer_reader(read)
	return function(ownbuf, sz)
		local buf, sz = read(sz)
		if not buf then return nil, sz end
		ffi.copy(ownbuf, buf, sz)
		return sz
	end
end

--make a `write(buf, sz)` that appends data to an expanding buffer.
function stream.growbuffer_writer(growbuffer)
	growbuffer = growbuffer or glue.growbuffer(nil, true)
	local i = 0
	return function(buf, sz)
		local dbuf = growbuffer(i + sz)
		ffi.copy(dbuf + i, buf, sz)
		i = i + sz
		return sz
	end, growbuffer
end

--convert `read(1) -> sz` to `read() -> n` which repeatedly calls
--`write(c, 1)` until EOL, excluding the EOL marker.
function stream.readline(read, write, crlf)
	return function()
		local n = 0
		while true do
			local buf, sz = read(1)
			if not buf then return nil, sz end
			assert(sz == 1)
			local c = buf[0]
			if c == 0x0A and not crlf then
				return n
			elseif c == 0x0D and crlf then
				local buf, sz = read(1)
				if not buf then return nil, sz end
				assert(sz == 1)
				local c = buf[0]
				if c == 0x0A then
					return n
				else
					return nil, 'LF expected'
				end
			else
				n = n + 1
				local sz, err = write(buf, 1)
				if not sz then return nil, err end
				assert(sz == 1)
			end
		end
	end
end

--call `read(buf, sz) -> sz` repeatedly until sz elements are read.
function stream.readexactly(buf, sz, read)
	local readsz, leftsz = 0, sz
	while leftsz > 0 do
		local sz, err = read(buf + readsz, leftsz)
		if not sz then return nil, err, leftsz end
		readsz = readsz + sz
		leftsz = leftsz - sz
	end
end
--call `write(buf, sz) -> sz` repeatedly until sz elements are written.
stream.writeexactly = stream.readexactly

--turn `read(sz) -> buf, sz` into `read(sz) -> s`
function stream.readstring(read)
	local buf, sz = read(sz)
	if not buf then return nil, sz end
	return ffi.string(buf, sz)
end

--convert `write(buf, sz) -> sz` to accept `write(s) -> sz`.
function stream.writestring(s, write)
	return function(buf, sz)
		return write(stringdata(buf, sz))
	end
end

--given `seek('cur') -> i` and `seek('cur', n) -> i`, convert `read(buf, sz)`
--to accept `read(nil, sz)` which skips sz elements.
function stream.make_skippable(read, seek, skipsz)
	if seek then
		return function(buf, sz)
			if not buf then --skip bytes
				local i0, err = seek()
				if not i0 then return nil, err end
				local i, err = seek('cur', sz)
				if not i then return nil, err end
				return i - i0
			else
				return read(buf, sz)
			end
		end
	else
		local skipbuf, skipsz = glue.growbuffer()(skipsz or 4096)
		return function(buf, sz)
			if not buf then
				local leftsz = sz
				while leftsz > 0 do
					local sz = math.min(skipsz, leftsz)
					local sz, err = stream.readexactly(skipbuf, sz, read)
					if not sz then return nil, err end
					leftsz = leftsz - sz
				end
			else
				return read(buf, sz)
			end
		end
	end
end

--[==[

-- returns a high level filter that cycles a low-level filter
function filter.cycle(low, ctx, extra)
    assert(low)
    return function(chunk)
        local ret
        ret, ctx = low(ctx, chunk, extra)
        return ret
    end
end

-- chains a bunch of filters together
-- (thanks to Wim Couwenberg)
function filter.chain(...)
    local arg = {...}
    local n = select('#',...)
    local top, index = 1, 1
    local retry = ""
    return function(chunk)
        retry = chunk and retry
        while true do
            if index == top then
                chunk = arg[index](chunk)
                if chunk == "" or top == n then return chunk
                elseif chunk then index = index + 1
                else
                    top = top+1
                    index = top
                end
            else
                chunk = arg[index](chunk or "")
                if chunk == "" then
                    index = index - 1
                    chunk = retry
                elseif chunk then
                    if index == n then return chunk
                    else index = index + 1 end
                else error("filter returned inappropriate nil") end
            end
        end
    end
end

-- Source stuff

-- create an empty source
local function empty()
    return nil
end

function source.empty()
    return empty
end

-- returns a source that just outputs an error
function source.error(err)
    return function()
        return nil, err
    end
end

-- creates a file source
function source.file(f, io_err)
    if handle then
        return function()
            local chunk = f:read(_M.BLOCKSIZE)
            if not chunk then f:close() end
            return chunk
        end
    else
        return source.error(io_err or 'unable to open file')
    end
end

-- turns a fancy source into a simple source
function source.simplify(src)
    assert(src)
    return function()
        local chunk, err_or_new = src()
        src = err_or_new or src
        if not chunk then return nil, err_or_new
        else return chunk end
    end
end

-- creates string source
function source.string(s)
    if s then
        local i = 1
        return function()
            local chunk = string.sub(s, i, i+_M.BLOCKSIZE-1)
            i = i + _M.BLOCKSIZE
            if chunk ~= "" then return chunk
            else return nil end
        end
    else return source.empty() end
end

-- creates rewindable source
function source.rewind(src)
    assert(src)
    local t = {}
    return function(chunk)
        if not chunk then
            chunk = table.remove(t)
            if not chunk then return src()
            else return chunk end
        else
            table.insert(t, chunk)
        end
    end
end

-- chains a source with one or several filter(s)
function source.chain(src, f, ...)
    if ... then f=filter.chain(f, ...) end
    assert(src and f)
    local last_in, last_out = "", ""
    local state = "feeding"
    local err
    return function()
        if not last_out then
            error('source is empty!', 2)
        end
        while true do
            if state == "feeding" then
                last_in, err = src()
                if err then return nil, err end
                last_out = f(last_in)
                if not last_out then
                    if last_in then
                        error('filter returned inappropriate nil')
                    else
                        return nil
                    end
                elseif last_out ~= "" then
                    state = "eating"
                    if last_in then last_in = "" end
                    return last_out
                end
            else
                last_out = f(last_in)
                if last_out == "" then
                    if last_in == "" then
                        state = "feeding"
                    else
                        error('filter returned ""')
                    end
                elseif not last_out then
                    if last_in then
                        error('filter returned inappropriate nil')
                    else
                        return nil
                    end
                else
                    return last_out
                end
            end
        end
    end
end

-- creates a source that produces contents of several sources, one after the
-- other, as if they were concatenated
-- (thanks to Wim Couwenberg)
function source.cat(...)
    local arg = {...}
    local src = table.remove(arg, 1)
    return function()
        while src do
            local chunk, err = src()
            if chunk then return chunk end
            if err then return nil, err end
            src = table.remove(arg, 1)
        end
    end
end

-- Sink stuff

-- creates a sink that stores into a table
function sink.table(t)
    t = t or {}
    local f = function(chunk, err)
        if chunk then table.insert(t, chunk) end
        return 1
    end
    return f, t
end

-- turns a fancy sink into a simple sink
function sink.simplify(snk)
    assert(snk)
    return function(chunk, err)
        local ret, err_or_new = snk(chunk, err)
        if not ret then return nil, err_or_new end
        snk = err_or_new or snk
        return 1
    end
end

-- creates a file sink
function sink.file(handle, io_err)
    if handle then
        return function(chunk, err)
            if not chunk then
                handle:close()
                return 1
            else return handle:write(chunk) end
        end
    else return sink.error(io_err or "unable to open file") end
end

-- creates a sink that discards data
local function null()
    return 1
end

function sink.null()
    return null
end

-- creates a sink that just returns an error
function sink.error(err)
    return function()
        return nil, err
    end
end

-- chains a sink with one or several filter(s)
function sink.chain(f, snk, ...)
    if ... then
        local args = { f, snk, ... }
        snk = table.remove(args, #args)
        f = filter.chain(unpack(args))
    end
    assert(f and snk)
    return function(chunk, err)
        if chunk ~= "" then
            local filtered = f(chunk)
            local done = chunk and ""
            while true do
                local ret, snkerr = snk(filtered, err)
                if not ret then return nil, snkerr end
                if filtered == done then return 1 end
                filtered = f(done)
            end
        else return 1 end
    end
end

-----------------------------------------------------------------------------
-- Pump stuff
-----------------------------------------------------------------------------
-- pumps one chunk from the source to the sink
function pump.step(src, snk)
    local chunk, src_err = src()
    local ret, snk_err = snk(chunk, src_err)
    if chunk and ret then return 1
    else return nil, src_err or snk_err end
end

-- pumps all data from a source to a sink, using a step function
function pump.all(src, snk, step)
    assert(src and snk)
    step = step or pump.step
    while true do
        local ret, err = step(src, snk)
        if not ret then
            if err then return nil, err
            else return 1 end
        end
    end
end

]==]

return stream
