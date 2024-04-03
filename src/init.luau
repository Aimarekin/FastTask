--[=[
	@class FastTask
]=]
local FastTask = {}

local FastTaskThread = require(script.FastTaskThread)
local FastTaskThreadProxy = require(script.FastTaskThreadProxy)

export type FastTaskThread = FastTaskThread.FastTaskThread

--[=[
	Functions like [FastTask.spawnControlled], except it does not return the thread.
	Prefer this function when you do not need to interact with the thread after it has been created.

	@within FastTask
	@param callback (A...) -> () -- The callback to run in the thread
	@param ... A... -- The arguments to run the callback with
	@return boolean -- Whether the thread was successfully resumed
	@return ...any -- The values returned by the thread, or the error message if the thread errored
]=]
function FastTask.spawn<A...>(callback: (A...) -> (), ...: A...): (boolean, ...any)
	local thread = FastTaskThread.untracked(callback)

	return coroutine.resume(thread, ...)
end

--[=[
	Mimics [task.spawn]. Creates a [FastTaskThread] and returns it, along with the result of the first resumption.
	The thread will resume immediately with the given arguments.

	@within FastTask
	@param callback (A...) -> () -- The callback to run in the thread
	@param ... A... -- The arguments to run the callback with
	@return FastTaskThread -- The created thread
	@return boolean -- Whether the thread was successfully resumed
	@return ...any -- The values returned by the thread, or the error message if the thread errored
]=]
function FastTask.spawnControlled<A...>(callback: (A...) -> (), ...: A...): (FastTaskThread, boolean, ...any)
	local thread = FastTaskThread.new(callback)

	return thread, thread:resume(...)
end

--[=[
	Functions like [FastTask.deferControlled], except it does not return the thread.
	Prefer this function when you do not need to interact with the thread after it has been created.

	@within FastTask
	@param callback (A...) -> () -- The callback to run in the thread
	@param ... A... -- The arguments to resume the thread with
]=]
function FastTask.defer<A...>(callback: (A...) -> (), ...: A...)
	local thread = FastTaskThread.untracked(callback)

	task.defer(thread, ...)
end

--[=[
	Mimics [task.defer]. Creates a [FastTaskThread] and returns it.
	The thread will resume automatically with the given arguments after the next resumption cycle.
	See defer's documentation for more information.

	@within FastTask
	@param callback (A...) -> () -- The callback to run in the thread
	@param ... A... -- The arguments to resume the thread with
]=]
function FastTask.deferControlled<A...>(callback: (A...) -> (), ...: A...): FastTaskThread
	local thread = FastTaskThread.new(callback)

	thread:defer(...)

	return thread
end

--[=[
	Functions like [FastTask.delayControlled], except it does not return the thread.
	Prefer this function when you do not need to interact with the thread after it has been created.

	@within FastTask
	@param duration number -- The seconds to wait before resuming the callback
	@param callback (A...) -> () -- The callback to run in the thread
	@param ... A... -- The arguments to resume the thread with
]=]
function FastTask.delay<A...>(duration: number, callback: (A...) -> (), ...: A...)
	local thread = FastTaskThread.untracked(callback)

	task.delay(duration, thread, ...)
end

--[=[
	Mimics [task.delay]. Creates a [FastTaskThread] and returns it.
	The thread will resume automatically with the given arguments after the duration has passed.

	@within FastTask
	@param duration number -- The seconds to wait before running the callback
	@param callback (A...) -> () -- The callback to run in the thread
	@param ... A... -- The arguments to resume the thread with
]=]
function FastTask.delayControlled<A...>(duration: number, callback: (A...) -> (), ...: A...): FastTaskThread
	local thread = FastTaskThread.new(callback)

	thread:delay(duration, ...)

	return thread
end

--[=[
	@function create
	Mimics [coroutine.create]. Creates a [FastTaskThread] and returns it.
	You can start, resume and interact with the thread using the methods provided by [FastTaskThread].

	@within FastTask
	@param callback () -> () -- The callback to run in the thread
	@return FastTaskThread
]=]
FastTask.create = FastTaskThread.new

--[=[
	Mimics [coroutine.wrap]. Creates a FastTaskThread and also returns a function which will call [FastTaskThread:next] on the created thread.

	@within FastTask
	@return (...any) -> (...any)
	@return FastTaskThread
]=]
function FastTask.wrap(callback: (...any) -> ()): ((...any) -> (...any), FastTaskThread)
	local thread = FastTaskThread.new(callback)

	local function wrappedResume(...: any): (...any)
		return thread:next(...)
	end

	return wrappedResume, thread
end

--[=[
	Creates two functions: one which will yield the coroutine it is called in, and another which will resume all the coroutines that have yielded.
	The arguments passed to the resume function will be passed as the return values of yield.
	These arguments will be stored, and any later calls to the yield function will return immediately.
	
	Attempting to call the resume function more than once will error.
	Attempting to call yield from a non-yieldable coroutine will also error. See [coroutine.isyieldable](https://create.roblox.com/docs/reference/engine/libraries/coroutine#isyieldable) for more information.

	If a yielded coroutine is resumed by something other than the resume function, yield() will error.

	Example:
	```lua
	local yield, resume = FastTask.resumable()

	FastTask.spawn(function()
		print("Running task!")
		print("Resumed with", yield())
	)

	print("Resuming task...")
	resume("hello", "world")
	```
	```
	Running task!
	Resuming task...
	Resumed with hello world
	```

	@within FastTask
	@return () -> (T...) -- Function which will yield the coroutine it is called in and return the arguments passed to the resume function
	@return (T...) -> () -- Function which will resume all the coroutines that have yielded and pass the arguments to the yield function
]=]
function FastTask.resumable<T...>(): (() -> (T...), (T...) -> ())
	local packedResumeArgs: {any}
	local yieldedCoroutines: {thread} = {}
	local hasResumed = false
	local currentlyResuming: thread?

	local function handleResumeResult(...)
		if currentlyResuming ~= coroutine.running() then
			error("Coroutine waiting for FastTask resumable was resumed by something else", 3)
		else
			return ...
		end
	end

	local function yield()
		if not hasResumed then
			if not coroutine.isyieldable() then
				error("Cannot yield from a non-yieldable coroutine", 2)
			end

			yieldedCoroutines[#yieldedCoroutines + 1] = coroutine.running()

			return handleResumeResult(coroutine.yield())
		else
			return unpack(packedResumeArgs)
		end
	end
	
	local function resume<T>(...: T...)
		if hasResumed then
			error("Cannot resume a resumable more than once", 2)
		end

		packedResumeArgs = {...}
		hasResumed = true

		for _, thread in yieldedCoroutines do
			currentlyResuming = thread
			coroutine.resume(thread, ...)
		end

		currentlyResuming = nil
		yieldedCoroutines = nil
	end

	return yield, resume
end

--[=[
	A more precise version of [task.wait], which will wait for the given duration in seconds, but will attempt to resume
	on every resumption cycle rather than on every [RunService.Heartbeat] event.

	The function will enter a loop that will yield the coroutine and resume it with [task.defer] until the time has passed.
	When the time has passed, the function will return the time waited in seconds.

	The function will return immediately if the duration is less than or equal to 0.

	@within FastTask
	@param duration number -- The time to wait in seconds
	@return number -- Actual time waited in seconds
]=]
function FastTask.deferredWait(duration: number): number
	local c = os.clock

	local startTime = c()

	if duration > 0 then
		local y = coroutine.yield

		local thisThread = coroutine.running()

		repeat
			task.defer(thisThread)
			y()
		until c() - startTime >= duration
	end

	return c() - startTime
end

--[=[
	@function proxyThread
	@within FastTask

	Creates an object identical to [FastTaskThread], but that does not track the thread, and can be used to interact with threads
	not created by FastTask.

	This function does not modify the lifecycle of the thread, meaning the thread will not be handled and reused by FastTask.

	@param thread thread -- The thread to make the proxy object interact with
	@return FastTaskThreadProxy
]=]
FastTask.proxyThread = FastTaskThreadProxy.new

return FastTask