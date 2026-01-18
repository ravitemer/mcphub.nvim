-- Get plugin root directory
---@return string
local function get_root()
    return vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h")
end

---@param msg string
---@param level? number default: TRACE
local function status(msg, level)
    vim.schedule(function()
        print(msg)
        --INFO: This is not working as expected
        -- coroutine.yield({
        --   msg = msg,
        --   level = level or vim.log.levels.TRACE,
        -- })
    end)
end

local root = get_root()

local function on_stdout(err, data)
    if data then
        status(data, vim.log.levels.INFO)
    end
    if err then
        status(err, vim.log.levels.ERROR)
    end
end

local function on_stderr(err, data)
    if data then
        status(data, vim.log.levels.ERROR)
    end
    if err then
        status(err, vim.log.levels.ERROR)
    end
end

status("Installing bundled script dependencies...", vim.log.levels.INFO)
local result = vim.system({
    "npm",
    "install",
}, {
    cwd = root .. "/scripts",
    stdout = on_stdout,
    stderr = on_stderr,
}):wait()
if result.code ~= 0 then
    status("Warning: Failed to install RPC proxy dependencies: " .. result.stderr, vim.log.levels.WARN)
else
    status("RPC proxy dependencies installed successfully", vim.log.levels.INFO)
end

status("Build complete!", vim.log.levels.INFO)
