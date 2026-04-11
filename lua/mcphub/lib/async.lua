local M = {}

local DEFAULT_WAIT_MS = 60000
local WAIT_INTERVAL_MS = 10

---@param fn fun(..., callback: function)
---@param _argc? integer
---@return function
function M.wrap(fn, _argc)
    return function(...)
        local args = { ... }
        local co = coroutine.running()

        if co then
            local done = false
            local results = nil

            local function callback(...)
                results = { ... }
                done = true
                if coroutine.status(co) == "suspended" then
                    local ok, err = coroutine.resume(co, unpack(results))
                    if not ok then
                        vim.schedule(function()
                            error(err)
                        end)
                    end
                end
            end

            table.insert(args, callback)
            fn(unpack(args))

            if done then
                return unpack(results or {})
            end

            return coroutine.yield()
        end

        local done = false
        local results = nil

        table.insert(args, function(...)
            results = { ... }
            done = true
        end)

        fn(unpack(args))
        vim.wait(DEFAULT_WAIT_MS, function()
            return done
        end, WAIT_INTERVAL_MS, false)

        return unpack(results or {})
    end
end

---@param fn fun()
---@param on_complete? function
function M.run(fn, on_complete)
    local co = coroutine.create(fn)

    local function step(...)
        local ok, err = coroutine.resume(co, ...)
        if not ok then
            error(err)
        end

        if coroutine.status(co) == "dead" and on_complete then
            on_complete()
        end
    end

    step()
end

return M
