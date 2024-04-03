local FastTaskThreadProxy = {}

--[=[
	@class FastTaskThreadProxy

	Proxy object for a thread not created by [FastTask] which mimics [FastTaskThread].
	This class exclusively handles interaction with the thread, and does not manage the thread's lifecycle.
	It is used to provide a consistent interface for threads created by [FastTask] and threads created by other means.

	You can create it using [FastTask.proxyThread].
]=]
local class = {}
local classMt = {}
FastTaskThreadProxy.class = class
FastTaskThreadProxy.classMt = classMt

export type FastTaskThreadProxy = {
	cancel: (self: FastTaskThreadProxy) -> (),
	close: (self: FastTaskThreadProxy) -> (boolean, string), -- assumed to not be nil due to type system support
	next: (self: FastTaskThreadProxy, ...any) -> ...any,
	resume: (self: FastTaskThreadProxy, ...any) -> (boolean, ...any),
	status: (self: FastTaskThreadProxy) -> "dead" | "normal" | "running" | "suspended",
	defer: (self: FastTaskThreadProxy, ...any) -> (),
	delay: (self: FastTaskThreadProxy, duration: number, ...any) -> (),
	traceback: (self: FastTaskThreadProxy, message: string) -> string,
}

type FastTaskThreadProxyPrivate = FastTaskThreadProxy & {
	_thread: thread
}

local function handleResumeClose(success: boolean, ...: any)
	if success then
		return ...
	else
		error(..., 3)
	end
end

--[=[
	@method cancel
	@within FastTaskThreadProxy

	Calls [FastTaskThreadProxy.close] on the thread, and errors if closing failed.
]=]
function class.cancel(self: FastTaskThreadProxyPrivate)
	handleResumeClose(self:close())
end

--[=[
	@method close
	@within FastTaskThreadProxy

	Calls [coroutine.close] on the thread.

	@return boolean -- Success
	@return string? -- Error message
]=]
function class.close(self: FastTaskThreadProxyPrivate)
	return coroutine.close(self._thread)
end

--[=[
	@method next
	@within FastTaskThreadProxy

	Calls [FastTaskThreadProxy.resume] and returns the values returned by the coroutine, or errors if the coroutine errored.

	@param ... any -- Arguments to pass to the coroutine
	@return ...any -- Values returned by the coroutine
]=]
function class.next(self: FastTaskThreadProxyPrivate, ...: any): ...any
	return handleResumeClose(self:resume(...))
end

--[=[
	@method resume
	@within FastTaskThreadProxy
	
	Calls [coroutine.resume] on the thread.

	@param ... any -- Arguments to pass to the coroutine
	@return boolean -- Success
	@return ...any -- Values returned by the coroutine, or an error message if the coroutine errored
]=]
function class.resume(self: FastTaskThreadProxyPrivate, ...: any): (boolean, ...any)
	return coroutine.resume(self._thread, ...)
end

--[=[
	@method status
	@within FastTaskThreadProxy
	
	Calls [coroutine.status] on the thread.

	@return "dead" | "normal" | "running" | "suspended"
]=]
function class.status(self: FastTaskThreadProxyPrivate): "dead" | "normal" | "running" | "suspended"
	return coroutine.status(self._thread)
end

function class.defer(self: FastTaskThreadProxyPrivate, ...)
	task.defer(self._thread, ...)
end

function class.delay(self: FastTaskThreadProxyPrivate, duration: number, ...)
	task.delay(duration, self._thread, ...)
end

--[=[
	@method traceback
	@within FastTaskThreadProxy
	
	Calls [debug.traceback] on the thread.

	@param message string? -- An error message to prepend to the traceback
	@param level number? -- Number of calls up the stack to return
	@return string
]=]
function class.traceback(self: FastTaskThreadProxyPrivate, message: string?, level: number?)
	return debug.traceback(self._thread, message, level)
end

function classMt.__tostring(self: FastTaskThreadProxyPrivate)
	return "FastTaskThreadWrapper " .. tostring(self._thread)
end

classMt.__index = class

--[=[
	Wraps a thread in a [FastTaskThreadProxy] object.

	Available as [FastTask.proxyThread] - prefer using that function over this constructor.

	@private
	@param thread thread -- The thread to wrap in the proxy
	@return FastTaskThreadProxy
]=]
function FastTaskThreadProxy.new(thread: thread): FastTaskThreadProxy
	return (setmetatable({
		_thread = thread
	}, classMt) ::  unknown) :: FastTaskThreadProxyPrivate
end

return FastTaskThreadProxy