local FastTask = {}

local FastTaskThread = require(script.FastTaskThread)

export type FastTaskThread = FastTaskThread.FastTaskThread

function FastTask.spawn<A..., R...>(callback: (A...) -> (R...), ...: A...)
	local thread = FastTaskThread.untracked(callback)

	coroutine.resume(thread, ...)
end

function FastTask.spawnControlled<A..., R...>(callback: (A...) -> (R...), ...: A...): FastTaskThread
	local thread = FastTaskThread.new(callback)

	thread:resume(...)

	return thread
end

function FastTask.defer<A..., R...>(callback: (A...) -> (R...), ...: A...)
	local thread = FastTaskThread.untracked(callback)

	task.defer(thread, ...)
end

function FastTask.deferControlled<A..., R...>(callback: (A...) -> (R...), ...: A...): FastTaskThread
	local thread = FastTaskThread.new(callback)

	thread:defer(...)

	return thread
end

function FastTask.delay<A..., R...>(duration: number, callback: (A...) -> (R...), ...: A...)
	local thread = FastTaskThread.untracked(callback)

	task.delay(duration, thread, ...)
end

function FastTask.delayControlled<A..., R...>(duration: number, callback: (A...) -> (R...), ...: A...): FastTaskThread
	local thread = FastTaskThread.new(callback)

	thread:delay(duration, ...)

	return thread
end

function FastTask.create<A..., R...>(callback: (A...) -> (R...)): FastTaskThread
	return FastTaskThread.new(callback)
end

function FastTask.wrap<A..., R...>(callback: (A...) -> (R...)): ((...any) -> (...any), FastTaskThread)
	local thread = FastTaskThread.new(callback)

	local function wrappedResume(...: any): (...any)
		return thread:continue(...)
	end

	return wrappedResume, thread
end

function FastTask.resumable<T...>(): (() -> (T...), (T...) -> ())
	local packedResumeArgs: {any}
	local yieldedCoroutines: {thread} = {}
	local hasResumed = false

	local function yield()
		if not hasResumed then
			local thread = coroutine.running()

			if not coroutine.isyieldable() then
				error("Cannot yield from a non-yieldable coroutine", 2)
			end

			yieldedCoroutines[#yieldedCoroutines + 1] = thread

			while true do
				coroutine.yield(thread)

				if hasResumed then
					break
				else
					warn("Coroutine waiting for resumable resumed before it was done")
				end
			end
		end

		return unpack(packedResumeArgs)
	end
	
	local function resume(...: T...)
		if hasResumed then
			error("Cannot resume a resumable more than once", 2)
		end

		packedResumeArgs = {...}
		hasResumed = true

		for _, thread in yieldedCoroutines do
			coroutine.resume(thread)
		end

		yieldedCoroutines = nil
	end

	return yield, resume
end


return FastTask