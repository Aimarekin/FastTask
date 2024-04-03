local FastTaskThread = {}

local THREAD_BODY_VERSION = 1

local freeThreads: {thread}
local globalThreadBodyName = "FastTaskThread_freeThreads_ver" .. THREAD_BODY_VERSION
if _G[globalThreadBodyName] then
	freeThreads = _G[globalThreadBodyName]
else
	freeThreads = {}
	_G[globalThreadBodyName] = freeThreads
end

local function coroutineErrorReporter(err: string?)
	warn("FastTaskThread errored. Traceback:", debug.traceback(err, 2) or "Traceback is empty")
	return err, debug.traceback(nil, 2)
end

local function xpcallCoroutineCallback(callback: (A...) -> (R...), ...: A...): (boolean, R...)
	return xpcall(callback, coroutineErrorReporter, ...)
end

local function coroutineBody()
	while true do
		local reportDone, reportDoneArg, callback = coroutine.yield()
		reportDone(reportDoneArg, xpcallCoroutineCallback(callback, coroutine.yield()))
	end
end

local function popFreeThread()
	if #freeThreads > 0 then
		local thread = freeThreads[#freeThreads]
		freeThreads[#freeThreads] = nil

		return thread
	else
		local thread = coroutine.create(coroutineBody)
		coroutine.resume(thread)
		return thread
	end
end

local function pushFreeThread(thread: thread)
	freeThreads[#freeThreads + 1] = thread
end

--[=[
	@class FastTaskThread

	Represents a thread created through FastTask.
	You can use this class to interact with threads safely, guaranteeing the thread will not be interacted with after it has finished
	and possibly reused.

	You can create instances of this class through [FastTask]'s controlled functions, [FastTask.create] and [FastTask.wrap].
]=]
local class = {}
local classMt = {}
FastTaskThread.class = class
FastTaskThread.classMt = classMt

export type FastTaskThread = {
	cancel: (self: FastTaskThread) -> (),
	close: (self: FastTaskThread) -> (boolean, string), -- assumed to not be nil due to type system support
	next: (self: FastTaskThread, ...any) -> ...any,
	resume: (self: FastTaskThread, ...any) -> (boolean, ...any),
	status: (self: FastTaskThread) -> "dead" | "normal" | "running" | "suspended",
	defer: (self: FastTaskThread, ...any) -> (),
	delay: (self: FastTaskThread, duration: number, ...any) -> (),
	traceback: (self: FastTaskThread, message: string) -> string,
}

type FastTaskThreadPrivate = FastTaskThread & {
	_thread: thread, -- assumed to not be nil due to type system support
	_finished: boolean?,
	_waitingForReturn: boolean?,
	_finishedSuccess: boolean?,
	_finishedReturns: { any }?,
	_traceback: string, -- assumed to not be nil due to type system support
	_markFinished: (self: FastTaskThread) -> (),
	_reportDone: (self: FastTaskThread, success: boolean, ...any) -> (),
}

function class._markFinished(self: FastTaskThreadPrivate)
	self._finished = true
	self._thread = nil
end

function class._reportDone(self: FastTaskThreadPrivate, success: boolean, ret1: any, ...: any)
	self:_markFinished()
	self._finishedSuccess = success
	if success then
		if self._waitingForReturn then
			self._finishedReturns = {...}
		end
	else
		if self._waitingForReturn then
			self._finishedReturns = {ret1}
		end
		self._traceback = ...
	end
	pushFreeThread(self._thread)
end

local function cancelHandleClose(success: boolean, errMessage: string)
	if success then
		return
	else
		error(errMessage, 3)
	end
end

--[=[
	@method cancel
	@within FastTaskThread

	Functions like [FastTaskThread.close], excepts it errors if there is a failure, instead of returning false and an error message.

	:::caution
	Closed threads can not be reused, negating the performance gain from thread reuse. Close threads sparingly.
	:::
]=]
function class.cancel(self: FastTaskThreadPrivate)
	if not self._finished then
		cancelHandleClose(self:close())
	end
end

--[=[
	@method close
	@within FastTaskThread
	Functions like [coroutine.close].
	The coroutine will attempt to be closed, preventing it from being resumed again. The thread will also be unable to be reused.
	If the coroutine fails to close, this function will return false and an error message. Otherwise, it will return true.

	:::caution
	Closed threads can not be reused, negating the performance gain from thread reuse. Close threads sparingly.
	:::

	@return boolean -- Success
	@return string? -- Error message
]=]
function class.close(self: FastTaskThreadPrivate)
	if self._finished then
		return true
	else
		local success, errMessage = coroutine.close(self._thread)
		if success then
			self:_markFinished()
		end
		return success, errMessage
	end
end

local function nextHandleResume(success: boolean, ...: any)
	if success then
		return ...
	else
		error(..., 3)
	end
end

--[=[
	@method next
	@within FastTaskThread

	Functions like [FastTaskThread.resume], excepts it errors if there is a failure, instead of returning false and an error message.

	@param ... any -- Arguments to pass to the coroutine
	@return ...any -- Values returned by the coroutine
]=]
function class.next(self: FastTaskThreadPrivate, ...: any): ...any
	return nextHandleResume(self:resume(...))
end

local function handleCoroutineResumeResult(self: FastTaskThreadPrivate, success: boolean, ...: any)
	if not success then
		warn("FastTaskThread coroutine errored internally: ", ...)
		return false, "FastTaskThread internal error: " .. ...
	else
		if self._finished then
			if not self._waitingForReturn then
				warn(
					"FastTaskThread errored internally and should've been waiting for result but wasn't - return values are not available. Traceback: ",
					debug.traceback("FastTaskThread was not waiting for return", 3)
				)
				return true, ...
			end
			local finishedSuccess, finishedRets = self._finishedSuccess, self._finishedReturns
			self._waitingForReturn = false
			-- Immediately erase returns to avoid storing them as they will not be needed again
			self._finishedSuccess = nil
			self._finishedReturns = nil

			return finishedSuccess, unpack(finishedRets)
		else
			self._waitingForReturn = false
			return true, ...
		end
	end
end

--[=[
	@method resume
	@within FastTaskThread

	Functions like [coroutine.resume].
	Starts or resumes the coroutine. The coroutine will run until it yields, returns or errors.
	If the coroutine yields or returns, this function will return true and the values passed to [coroutine.yield] or the returns.
	If the coroutine errors, this function will return false the error message.

	@param ... any -- Arguments to pass to the coroutine
	@return boolean -- Success
	@return ...any -- Values returned by the coroutine, or an error message if the coroutine errored
]=]
function class.resume(self: FastTaskThreadPrivate, ...: any): (boolean, ...any)
	if self._finished then
		return false, "cannot resume dead coroutine"
	else
		self._waitingForReturn = true
		return handleCoroutineResumeResult(self, coroutine.resume(self._thread, ...))
	end
end

--[=[
	@method status
	@within FastTaskThread

	Mimics [coroutine.status].
	Returns the status of the coroutine. See [coroutine.status] for more information.

	The function will return "dead" if the task has finished running (and the thread might have been reused).
	Otherwise, it will return the status of the coroutine through [coroutine.status].

	@return "dead" | "normal" | "running" | "suspended"
]=]
function class.status(self: FastTaskThreadPrivate): "dead" | "normal" | "running" | "suspended"
	if self._finished then
		return "dead"
	else
		return coroutine.status(self._thread)
	end
end

--[=[
	@method defer
	@within FastTaskThread

	Mimics [task.defer].
	Schedules the thread to be resumed in the next resumption cycle with the given arguments.
	See [task.defer] for more information.

	The thread will not be resumed if it has finished running.
	The thread can still be resumed with [FastTaskThread.resume], but the defer will still be scheduled.

	@param ... any -- Arguments to pass to the coroutine
]=]
function class.defer(self: FastTaskThreadPrivate, ...: any)
	if self._finished then
		return
	else
		local helperThread = FastTaskThread.untracked(coroutine.resume)
		task.defer(helperThread, self._thread, ...)
	end
end

--[=[
	@method delay
	@within FastTaskThread

	Mimics [task.delay].
	Schedules the thread to be resumed in the next [RunService.Heartbeat] after `duration` seconds with the given arguments.

	The thread will not be resumed if it has finished running.
	The thread can still be resumed with [FastTaskThread.resume], but the delay will still be scheduled.

	@param duration number -- The duration in seconds to wait before resuming the coroutine
	@param ... any -- Arguments to pass to the coroutine
]=]
function class.delay(self: FastTaskThreadPrivate, duration: number, ...: any)
	if self._finished then
		return
	else
		local helperThread = FastTaskThread.untracked(coroutine.resume)
		task.delay(duration, helperThread, self._thread, ...)
	end
end

--[=[
	@method traceback
	Mimics [debug.traceback] when called with a thread as first argument.
	
	If the thread has finished and errored, the function will return the error message and the stored traceback.
	The level argument will trim the first level - 1 lines.
	Otherwise, it will return the traceback of the coroutine through [debug.traceback].

	Mind that the traceback will contain extra lines at the end from the thread reusing mechanism.

	@param message string? -- An error message to prepend to the traceback
	@param level number? -- Number of calls up the stack to return
	@return string
	@within FastTaskThread
]=]
function class.traceback(self: FastTaskThreadPrivate, message: string?, level: number?)
	if level and level < 0 then
		error("level must be non-negative", 2)
	end

	if self._finished then
		local trace = self._traceback
		if trace and level > 1 then
			local lines = string.split(trace, "\n")
			trace = ""
			if level < #lines then
				for _, v in next, lines, level - 1 do
					trace = trace .. v .. "\n"
				end
			end
		end

		if message then
			return message .. "\n" .. trace
		else
			return trace
		end
	else
		return debug.traceback(self._thread, message, level)
	end
end

function classMt.__tostring(self: FastTaskThreadPrivate)
	return "FastTaskThread " .. tostring(self._thread)
end

classMt.__index = class

--[=[
	Creates a new FastTaskThread with the given callback as its body.

	Available as [FastTask.create] - prefer using that function over this constructor.

	@private
	@param callback () -> () -- The callback to run in the thread
	@return FastTaskThread
]=]
function FastTaskThread.new(callback: (...any) -> ()): FastTaskThread
	local thread = popFreeThread()

	local self = setmetatable({
		_thread = thread
	}, classMt)

	coroutine.resume(thread, class._reportDone, self, callback)

	return self
end

--[=[
	Pulls a thread from the pool of free threads and assigns it the given callback body.
	This function does not track the thread, and will not return a FastTaskThread object.

	:::warning
	Do not use untracked threads, as they are unsafe: they are not tracked by the FastTask library,
	allowing the thread to be interacted with even after being reused.
	Instead use the [FastTask] library's functions, who will already use untracked threads when not using controlled threads
	as a performance optimization.
	:::	

	@private
	@param callback () -> () -- The callback to run in the thread
	@return thread
]=]
function FastTaskThread.untracked(callback: (...any) -> ()): thread
	local thread = popFreeThread()

	coroutine.resume(thread, pushFreeThread, thread, callback)

	return thread
end

return FastTaskThread