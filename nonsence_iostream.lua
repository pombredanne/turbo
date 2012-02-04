--[[
	
	Nonsence Asynchronous event based Lua Web server.
	Author: John Abrahamsen < JhnAbrhmsn@gmail.com >
	
	This module "IOLoop" is a part of the Nonsence Web server.
	< https://github.com/JohnAbrahamsen/nonsence-ng/ >
	
	Nonsence is licensed under the MIT license < http://www.opensource.org/licenses/mit-license.php >:

	"Permission is hereby granted, free of charge, to any person obtaining a copy of
	this software and associated documentation files (the "Software"), to deal in
	the Software without restriction, including without limitation the rights to
	use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
	of the Software, and to permit persons to whom the Software is furnished to do
	so, subject to the following conditions:

	The above copyright notice and this permission notice shall be included in all
	copies or substantial portions of the Software.

	THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
	IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
	FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
	AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
	LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
	OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
	SOFTWARE."

  ]]
  
-------------------------------------------------------------------------
--
-- Load modules
--
local log = assert(require('nonsence_log'), 
	[[Missing nonsence_log module]])
local nixio = assert(require('nixio'),
	[[Missing required module: Nixio (https://github.com/Neopallium/nixio)]])
local ioloop = assert(require('nonsence_ioloop'), 
	[[Missing nonsence_ioloop module]])
assert(require('yacicode'), 
[[Missing required module: Yet Another class Implementation http://lua-users.org/wiki/YetAnotherClassImplementation]])
-------------------------------------------------------------------------

-------------------------------------------------------------------------
-- Speeding up globals access with locals :>
--
local xpcall, pcall, random, newclass, pairs, ipairs, os, bitor, 
bitand = xpcall, pcall, math.random, newclass, pairs, ipairs, os, 
nixio.bit.bor, nixio.bit.band
-------------------------------------------------------------------------
-- Table to return on require.
local iostream = {}
-------------------------------------------------------------------------

local dump = log.dump

iostream.IOStream = newclass('IOStream')

function iostream.IOStream:init(socket, io_loop, max_buffer_size, read_chunk_size)
	self.socket = assert(socket, [[Please provide a socket for IOStream:new()]])
	self.socket:setblocking(false)
	self.io_loop = io_loop or ioloop.IOLoop:new()
	self.max_buffer_size = max_buffer_size or 104857600
	self.read_chunk_size = read_chunk_size or 4096
	self._read_buffer = {}
	self._write_buffer = {}
	self._read_buffer_size = 0
	self._write_buffer_frozen = false
	self._read_delimiter = nil
	self._read_pattern = nil
	self._read_bytes = nil
	self._read_until_close = false
	self._read_callback = nil
	self._streaming_callback = nil
	self._write_callback = nil
	self._close_callback = nil
	self._connect_callback = nil
	self._connecting = false
	self._state = nil
	self._pending_callbacks = 0
end

function iostream.IOStream:connect(address, port, callback)
	-- Connect to a address without blocking.
	-- Address can be a IP or DNS domain.
	
	self._connecting = true
	
	self.socket:connect(address, port)
	-- Set callback.
	self._connect_callback = callback
	self:_add_io_state(ioloop.WRITE)
end

function iostream.IOStream:read_until_pattern(pattern, callback)
	-- Call callback when the given pattern is read.
	
	assert(( not self._read_callback ), "Already reading.")
	self._read_pattern = pattern
	while true do
		if self._read_from_buffer() then
			return
		end
		if self._read_to_buffer() == 0 then
			-- Buffer exhausted. Break.
			break
		end
	end
	self._add_io_state(ioloop.READ)
end

function iostream.IOStream:_handle_read()

end

function iostream.IOStream:_handle_events(file_descriptor, events)
	-- Handle events
	
	if not self.socket then 
		-- Connection has been closed. Can not handle events...
		log.warning([[_handle_events() got events for closed sockets.]])
		return
	end
	
	-- Handle different events.
	if bitor(events, ioloop.READ) then
		self._handle_read()
	end
	if not self.socket then 
		return
	end
	if bitor(events, ioloop.WRITE) then
		self._handle_write()
	end
	if not self.socket then 
		return
	end
	if bitor(events, ioloop.ERROR) then
		-- TODO handle callbacks.
		local function _close_wrapper()
			self.close(self)
		end
		self.io_loop:add_callback(_close_wrapper)
		return
	end
	
end

function iostream.IOStream:reading()
	return ( not not self._read_callback )
end

function iostream.IOStream:writing()
	return ( not not self._write_buffer )
end

function iostream.IOStream:closed()
	return ( not not self.socket )
end

function iostream.IOStream:_read_from_socket()
	-- Reads from the socket.
	-- Return the data chunk or nil if theres nothing to read.
	
	local chunk = self.socket:recv(self.read_chunk_size)
	
	if not chunk then 
		self:close()
		return nil
	end
	
	return chunk
end

function iostream.IOStream:_read_to_buffer()
	-- Read from the socket and append to the read buffer.
	
	local chunk = self._read_from_socket()
	if not chunk then
		return 0
	end
	self._read_buffer = self._read_buffer .. chunk
	self._read_buffer_size = self._read_buffer:len()
	if self._read_buffer_size >= self.max_buffer_size then
		logging.error('Reached maximum read buffer size')
		self:close()
		return
	end
	return chunk:len()
end

function iostream.IOStream:_add_io_state(state)
	-- Add IO state to IOLoop.

	if not self.socket then
		-- Connection has been closed, can not add state.
		return
	end

	if not self._state then
		self._state = bitor(ioloop.ERROR, state)
		local function _handle_events_wrapper(file_descriptor, events)
			self._handle_events(self, file_descriptor, events)
		end
		self.io_loop:add_handler(self.socket:fileno(), self._state, _handle_events_wrapper )
	elseif not bitand(self._state, state) then
		self._state = bitor(self._state, state)
		self.io_loop:update_handler(self.socket:fileno(), self._state)
	end
	
end

-------------------------------------------------------------------------
-- Return ioloop table to requires.
return iostream
-------------------------------------------------------------------------
