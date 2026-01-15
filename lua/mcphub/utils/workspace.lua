local M = {}

local uv = (vim.loop or vim.uv)
local path = require("plenary.path")
local utils = require("mcphub.utils")

---Search upward from current directory for any of the look_for files
---@param look_for_patterns string[] Array of file patterns to look for
---@param start_dir? string Starting directory (defaults to current working directory)
---@return table|nil { root_dir = "/path", config_file = "/path/.vscode/mcp.json" } or nil
function M.find_workspace_config(look_for_patterns, start_dir)
    start_dir = start_dir or vim.fn.getcwd()

    local current_dir = path:new(start_dir)
    local parent_dir = current_dir:parent()
    -- Search upward until we hit the root
    while current_dir and tostring(current_dir) ~= tostring(parent_dir) do
        -- Check each pattern in order
        for _, pattern in ipairs(look_for_patterns) do
            local config_file = current_dir / pattern
            if config_file:exists() then
                return {
                    root_dir = tostring(current_dir),
                    config_file = tostring(config_file),
                }
            end
        end

        -- Move up one directory
        current_dir = parent_dir
        parent_dir = current_dir:parent()
    end

    return nil
end

---Hash workspace path to generate a consistent port
---@param workspace_path string Absolute path to workspace root
---@param port_range table {min: number, max: number}
---@return number Generated port number
function M.generate_workspace_port(workspace_path, port_range)
    -- Simple hash function using string bytes
    local hash = 0
    for i = 1, #workspace_path do
        hash = (hash * 31 + string.byte(workspace_path, i)) % 2147483647
    end

    -- Map hash to port range
    local range_size = port_range.max - port_range.min + 1
    return port_range.min + (hash % range_size)
end

---Check if a port is available
---@param port number Port number to check
---@return boolean True if port is available
function M.is_port_available(port)
    local handle = uv.new_tcp()
    if not handle then
        return false
    end

    local success = handle:bind("127.0.0.1", port)
    handle:close()

    return success
end

---Find next available port starting from generated port
---@param opts { port_range: table, workspace_path?: string, max_attempts?: number }? Options to search for available port
---@return number|nil Available port number or nil if none found
function M.find_available_port(opts)
    opts = vim.tbl_extend("force", {
        max_attempts = 100,
    }, opts or {})

    ---@type number
    local base_port
    if opts.workspace_path then
        base_port = M.generate_workspace_port(opts.workspace_path, opts.port_range)
    else
        math.randomseed(os.time() + vim.fn.getpid())
        local range_size = opts.port_range.max - opts.port_range.min + 1
        base_port = opts.port_range.min + math.random(0, range_size - 1)
    end

    for i = 0, opts.max_attempts - 1 do
        local port = base_port + i

        -- Wrap around if we exceed max port
        if port > opts.port_range.max then
            port = opts.port_range.min + (port - opts.port_range.max - 1)
        end

        if M.is_port_available(port) then
            return port
        end
    end

    return nil
end

---Get the path to the global workspace cache file
---@return string Absolute path to workspace cache file
function M.get_workspace_cache_path()
    -- Get home directory using Neovim's cross-platform approach
    local home = vim.fn.expand("~")

    if not home or home == "~" then
        -- Fallback to environment variables if expand fails
        home = os.getenv("HOME")
            or os.getenv("USERPROFILE")
            or (os.getenv("HOMEDRIVE") and os.getenv("HOMEPATH") and (os.getenv("HOMEDRIVE") .. os.getenv("HOMEPATH")))
    end

    if not home then
        error("Unable to determine user home directory")
    end

    -- Check for legacy path first (same logic as backend)
    local legacy_path = vim.fs.joinpath(home, ".mcp-hub", "workspaces.json")

    -- Use legacy path if it exists (matching backend behavior)
    if vim.fn.filereadable(legacy_path) == 1 then
        return legacy_path
    end

    -- Otherwise use XDG-compliant path
    local state_home = os.getenv("XDG_STATE_HOME") or vim.fs.joinpath(home, ".local", "state")
    local cache_dir = vim.fs.joinpath(state_home, "mcp-hub")
    return vim.fs.joinpath(cache_dir, "workspaces.json")
end

---Read the global workspace cache from mcp-hub's state directory
---@return table Table of workspace_path -> {pid, port, startTime}
function M.read_workspace_cache()
    local cache_path = M.get_workspace_cache_path()
    local cache_file = path:new(cache_path)

    if not cache_file:exists() then
        return {}
    end

    local content = cache_file:read()
    if not content or content == "" then
        return {}
    end

    local success, cache = utils.json_decode(content)
    if not success then
        vim.notify("Failed to parse workspace cache: " .. cache_path, vim.log.levels.WARN)
        return {}
    end

    return cache or {}
end

---Check if a process is still running
---@param pid number Process ID to check
---@return boolean True if process is running
function M.is_process_running(pid)
    if not pid or type(pid) ~= "number" then
        return false
    end

    -- Use kill with signal 0 to check if process exists
    local success = pcall(function()
        uv.kill(pid, 0)
    end)

    return success
end

---Get active hub info for a workspace
---@param port string current port of the hub
---@return table|nil {port, pid, startTime, config_files} or nil if no active hub
function M.get_workspace_hub_info(port)
    port = tostring(port) -- Ensure port is a string
    local cache = M.read_workspace_cache()
    local entry = cache[port]

    if not entry then
        return nil
    end

    -- Check if the process is still running
    if not M.is_process_running(entry.pid) then
        return nil
    end

    return entry
end

-- Enhanced function to find matching hub by workspace + config
function M.find_matching_workspace_hub(workspace_path, config_files)
    local cache = M.read_workspace_cache()

    -- Search through ALL cache entries (keyed by port now)
    for port_str, entry in pairs(cache) do
        -- Check if workspace matches
        if entry.cwd == workspace_path then
            -- Check if config files match
            if vim.deep_equal(entry.config_files or {}, config_files) then
                -- Check if process is still running
                if M.is_process_running(entry.pid) then
                    return {
                        port = entry.port,
                        pid = entry.pid,
                        startTime = entry.startTime,
                        config_files = entry.config_files,
                        workspace_path = entry.cwd,
                    }
                end
            end
        end
    end

    return nil
end

---Check if workspace mode is enabled
---@return boolean True if workspace mode is enabled
function M.is_workspace_enabled()
    local State = require("mcphub.state")
    return State.config and State.config.workspace and State.config.workspace.enabled == true
end

return M
