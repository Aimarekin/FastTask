local FastTaskThread = {}

local freeThreads: { thread } = {}

local function runCoroutineCallback<T...>(callback: (T...) -> (), ...: T...)
	callback(...)
end

local function coroutineErrorReporter(err)
	warn("FastTaskThread errored and has been catched to reuse thread (trace below):")
	warn(debug.traceback(err, 2))
end

local function coroutineBody()
	while true do
		local reportDone, reportDoneArg, callback = coroutine.yield()
		reportDone(reportDoneArg, xpcall(runCoroutineCallback, coroutineErrorReporter, callback, coroutine.yield()))
	end
end

local function popFreeThread()
	if #freeThreads > 0 then
		local thread = freeThreads[#freeThreads]
		freeThreads[#freeThreads] = nil

		return thread
	else
		return task.spawn(coroutineBody)
	end
end

local function pushFreeThread(thread: thread)
	freeThreads[#freeThreads + 1] = thread
end

local class = {}
local classMt = {}

export type FastTaskThread = {
	close: (self: FastTaskThread) -> (boolean, any),
	continue: (self: FastTaskThread, ...any) -> ...any,
	resume: (self: FastTaskThread, ...any) -> (boolean, ...any),
	status: (self: FastTaskThread) -> "dead" | "normal" | "running" | "suspended",
	defer: (self: FastTaskThread, ...any) -> (),
	delay: (self: FastTaskThread, duration: number, ...any) -> ()
}

function class:_reportDone(success: boolean, ...: any)
	self._finished = true
	self._finishedSuccess = success
	self._finishedReturns = table.pack(...)
	pushFreeThread(self._thread)
end

function class:_handleCoroutineResumeResult(success: boolean, ...: any)
	if not success then
		error("FastTaskThread coroutine errored internally: " .. ...)
	else
		if self._hasFinished then
			return self._finishedSuccess, unpack(self._finishedReturns)
		else
			return true, ...
		end
	end
end

function class:close()
	if self._hasFinished then
		return true
	else
		return coroutine.close(self._thread)
	end
end

local function handleContinueFastTaskThreadResumeResult(success: boolean, ...:any)
	if success then
		return ...
	else
		error(..., 3)
	end
end

function class:continue(...)
	return handleContinueFastTaskThreadResumeResult(self:resume(...))
end

function class:resume(...)
	if self._hasFinished then
		return false, "cannot resume dead coroutine"
	else
		return self:_handleCoroutineResumeResult(coroutine.resume(self._thread, ...))
	end
end

function class:status()
	if self._hasFinished then
		return "dead"
	else
		return coroutine.status(self._thread)
	end
end

function class:defer(...)
	if self._hasFinished then
		return
	else
		local helperThread = FastTaskThread.untracked(class.continue)
		task.defer(helperThread, self, ...)
	end
end

function class:delay(duration: number, ...)
	if self._hasFinished then
		return
	else
		local helperThread = FastTaskThread.untracked(class.continue)
		task.delay(duration, helperThread, self, ...)
	end
end

function classMt:__tostring()
	return "FastTaskThread " .. tostring(self._thread)
end

classMt.__index = class


function FastTaskThread.new<A..., R...>(callback: (A...) -> (R...)): FastTaskThread
	local thread = popFreeThread()

	local self = setmetatable({
		_thread = thread
	}, classMt)

	coroutine.resume(thread, class._reportDone, self, callback)

	return self
end

function FastTaskThread.untracked<A..., R...>(callback: (A...) -> (R...)): thread
	local thread = popFreeThread()

	coroutine.resume(thread, pushFreeThread, thread, callback)

	return thread
end

return FastTaskThread