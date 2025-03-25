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
local bundled = root .. "/bundled/mcp-hub"

-- Clean
status("Cleaning bundled directory...")
if vim.fn.isdirectory(bundled) == 1 then
    vim.fn.delete(bundled, "rf")
end

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

-- Create directory
status("Creating bundled directory...")
vim.fn.mkdir(bundled, "p")

-- Initialize npm
status("Initializing npm project...")
local npm_init_result = vim.system({
    "npm",
    "init",
    "-y",
}, {
    cwd = bundled,
    stdout = false,
    stderr = on_stderr,
}):wait()

if npm_init_result.code ~= 0 then
    error("Failed to initialize npm project: " .. npm_init_result.stderr)
else
    -- Install mcp-hub
    status("Installing mcp-hub...", vim.log.levels.INFO)
    local npm_install_result = vim.system({
        "npm",
        "install",
        "mcp-hub@latest",
    }, {
        cwd = bundled,
        stdout = on_stdout,
        stderr = on_stderr,
    }):wait()
    if npm_install_result.code ~= 0 then
        error("Failed to install mcp-hub: " .. npm_install_result.stderr)
    else
        status("Build complete!", vim.log.levels.INFO)
    end
end
