return function()
    local FastTaskThread = require(game.ReplicatedStorage.FastTask.FastTaskThread)

    local LogService = game:GetService("LogService")

    local function emptyFunc()
        -- EMPTY
    end

    describe("FastTaskThread", function()
        it("should reuse threads", function()
            local thread = FastTaskThread.untracked(emptyFunc)
            coroutine.resume(thread)
            expect(FastTaskThread.untracked(emptyFunc)).to.equal(thread)
        end)

        it("should correctly return yielded and resumed values", function()
            local thread = FastTaskThread.new(function(value)
                expect(value).to.equal("A")
                expect(coroutine.yield("B")).to.equal("C")
                return "D"
            end)
            expect(thread:resume("A")).to.equal(true, "B")
            expect(thread:resume("C")).to.equal(true, "D")
        end)

        it("should correctly return yielded and resumed values with next", function()
            local thread = FastTaskThread.new(function(value)
                expect(value).to.equal("A")
                expect(coroutine.yield("B")).to.equal("C")
                return "D"
            end)
            expect(thread:next("A")).to.equal("B")
            expect(thread:next("C")).to.equal("D")
        end)

        it("should error when throwing with next", function()
            local thread = FastTaskThread.new(error)
            expect(function()
                thread:next("A")
            end).to.throw("A")
        end)

        it("should correctly report the status of a thread", function()
            local thread
            thread = FastTaskThread.new(function()
                local thisThread = coroutine.running()
                coroutine.yield(coroutine.status(thisThread))
                coroutine.resume(coroutine.create(function() 
                    expect(thread:status()).to.equal("normal")
                end))
            end)
            expect(thread:status()).to.equal("suspended")

            expect(thread:resume()).to.equal(true, "running")

            thread:resume()
            expect(thread:status()).to.equal("dead")
        end)

        it("should correctly report the status of an errored thread", function()
            local thread = FastTaskThread.new(error)
            expect(thread:status()).to.equal("suspended")
            expect(thread:resume()).to.equal(false)
            expect(thread:status()).to.equal("dead")
        end)

        it("should correctly report the status of a finished thread as dead after reusing", function()
            local thread1 = FastTaskThread.new(emptyFunc)
            expect(thread1:status()).to.equal("suspended")
            
            thread1:resume()
            expect(thread1:status()).to.equal("dead")

            local thread2 = FastTaskThread.new(emptyFunc)
            expect(thread1:status()).to.equal("dead")
            expect(thread2:status()).to.equal("suspended")

            thread2:resume()
            expect(thread1:status()).to.equal("dead")
            expect(thread2:status()).to.equal("dead")
        end)

        it("should not allow resuming dead threads", function()
            local thread = FastTaskThread.new(emptyFunc)
            expect(thread:resume(thread)).to.equal(true)
            expect(thread:resume(thread)).to.equal(false, "cannot resume dead coroutine")
        end)

        it("should not allow resuming reused threads", function()
            local thread = FastTaskThread.new(emptyFunc)
            expect(thread:resume(thread)).to.equal(true)
            expect(thread:resume(thread)).to.equal(false, "cannot resume dead coroutine")
            
            FastTaskThread.untracked(emptyFunc)
            expect(thread:resume(thread)).to.equal(false, "cannot resume dead coroutine")
        end)

        it("should return false and error message when erroring inside thread", function()
            local thread = FastTaskThread.new(error)
            expect(thread:resume("A")).to.equal(false, "A")
        end)

        it("should not allow resuming errored threads", function()
            local thread = FastTaskThread.new(error)
            expect(thread:resume(thread)).to.equal(false)
            expect(thread:resume(thread)).to.equal(false, "cannot resume dead coroutine")
        end)

        it("should reuse errored threads", function()
            local thread = FastTaskThread.untracked(error)
            expect(coroutine.resume(thread)).to.equal(true, false)
            expect(FastTaskThread.untracked(emptyFunc)).to.equal(thread)
        end)

        it("should allow cancelling threads", function()
            local iter = 0
            local thread = FastTaskThread.new(function()
                while true do
                    iter += 1
                    coroutine.yield()
                end
            end)

            thread:resume()
            expect(iter).to.equal(1)

            thread:cancel()
            expect(iter).to.equal(1)

            thread:resume()
            expect(iter).to.equal(1)
        end)
    end)
end