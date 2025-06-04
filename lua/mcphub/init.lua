local Error = require("mcphub.utils.errors")
local ImageCache = require("mcphub.utils.image_cache")
local Job = require("plenary.job")
local MCPHub = require("mcphub.hub")
local State = require("mcphub.state")
local log = require("mcphub.utils.log")
local native = require("mcphub.native")
local utils = require("mcphub.utils")
local validation = require("mcphub.utils.validation")

---@class MCPHub
local M = {
    is_native_server = native.is_native_server,
    add_server = native.add_server,
    add_tool = native.add_tool,
    add_resource = native.add_resource,
    add_resource_template = native.add_resource_template,
    add_prompt = native.add_prompt,
}

---Get the current MCPHub instance
---@return MCPHub.Hub | nil
function M.get_hub_instance()
    if State.setup_state ~= "completed" then
        return nil
    end
    return State.hub_instance
end

---Get the current state of the MCPHub
---@return MCPHub.State
function M.get_state()
    return State
end

---@param event string | table
---@param callback fun(data: table)
function M.on(event, callback)
    --if event is an array then add each event
    if type(event) == "table" then
        for _, e in ipairs(event) do
            State:add_event_listener(e, callback)
        end
        return
    end
    State:add_event_listener(event, callback)
end

---@param event string | table
---@param callback fun(data: table)
function M.off(event, callback)
    --if event is an array then remove each event
    if type(event) == "table" then
        for _, e in ipairs(event) do
            State:remove_event_listener(e, callback)
        end
        return
    end
    State:remove_event_listener(event, callback)
end

--- Setup MCPHub plugin with error handling and validation
--- @param opts MCPHub.Config?
---@return MCPHub.Hub | nil
function M.setup(opts)
    ---@param err MCPError
    local function _on_setup_failed(err)
        if err then
            State:add_error(err)
            State:update({
                setup_state = "failed",
            }, "setup")
            State.config.on_error(tostring(err))
        end
    end

    ---Version check handler
    ---@param job Job
    ---@param code number
    ---@param config MCPHub.Config
    local function _handle_version_check(job, code, config)
        if code ~= 0 then
            return _on_setup_failed(
                Error(
                    "SETUP",
                    Error.Types.SETUP.MISSING_DEPENDENCY,
                    "mcp-hub exited with non-zero code. Please verify your installation."
                )
            )
        end

        -- Validate version
        local version_result = validation.validate_version(job:result()[1])
        if not version_result.ok then
            return _on_setup_failed(version_result.error)
        end

        -- Create hub instance
        local hub = MCPHub:new(config)
        if not hub then
            return _on_setup_failed(Error("SETUP", Error.Types.SETUP.SERVER_START, "Failed to create MCPHub instance"))
        end

        State.hub_instance = hub
        State:update({
            setup_state = "completed",
        }, "setup")

        -- Initialize image cache
        ImageCache.setup()

        -- Setup Extensions
        require("mcphub.extensions").setup("avante", config.extensions.avante)
        -- Start hub
        hub:start()
    end
    -- Return if already setup or in progress
    if State.setup_state ~= "not_started" then
        return State.hub_instance
    end
    -- Update state to in_progress
    State:update({
        setup_state = "in_progress",
    }, "setup")
    local config = require("mcphub.config").setup(opts)
    local cmds = utils.get_default_cmds(config)
    config.cmd = cmds.cmd
    config.cmdArgs = cmds.cmdArgs
    if config.auto_approve then
        vim.g.mcphub_auto_approve = vim.g.mcphub_auto_approve == nil and true or vim.g.mcphub_auto_approve
    end
    log.setup(config.log)
    State.ui_instance = require("mcphub.ui"):new(config.ui)
    State.config = config
    vim.api.nvim_create_user_command("MCPHub", function(args)
        if State.ui_instance then
            State.ui_instance:toggle(args)
        else
            State:add_error(Error("RUNTIME", Error.Types.RUNTIME.INVALID_STATE, "UI not initialized"))
        end
    end, {
        desc = "Toggle MCP Hub window",
    })

    -- Validate options
    local validation_result = validation.validate_setup_opts(config)
    if not validation_result.ok then
        return _on_setup_failed(validation_result.error)
    end

    -- Update servers config in state
    local file_result = validation.validate_config_file(config.config)
    if file_result.ok and file_result.json then
        State.servers_config = file_result.json.mcpServers or {}
        State.native_servers_config = file_result.json.nativeMCPServers or {}
    else
        return _on_setup_failed(file_result.error)
    end
    local Native = require("mcphub.native")
    Native.setup()
    -- Initialize native servers if any provided in setup config
    if config.native_servers then
        for name, def in pairs(config.native_servers) do
            local server = Native.register(def)
            if server then
                -- make sure the server name is set to key
                server.name = name
            end
        end
    end

    -- Setup cleanup
    local group = vim.api.nvim_create_augroup("mcphub_cleanup", {
        clear = true,
    })
    vim.api.nvim_create_autocmd("VimLeavePre", {
        group = group,
        callback = function()
            if State.hub_instance then
                State.hub_instance:stop()
            end
            -- UI cleanup is handled by its own autocmd
        end,
    })

    -- Start version check
    local ok, job = pcall(function()
        ---@diagnostic disable-next-line: missing-fields
        return Job:new({
            command = config.cmd,
            args = utils.clean_args({ config.cmdArgs, "--version" }),
            on_exit = vim.schedule_wrap(function(j, code)
                _handle_version_check(j, code, config)
            end),
        })
    end)

    local help_msg = [[mcp-hub executable not found. Please ensure:
1. For global install: Run 'npm install -g mcp-hub@latest'
2. For bundled install: Set build = 'bundled_build.lua' in lazy spec and use_bundled_binary = true in config.
3. For custom install: Verify cmd/cmdArgs point to valid mcp-hub executable
]]
    if not ok then
        -- Handle executable not found error
        return _on_setup_failed(Error("SETUP", Error.Types.SETUP.MISSING_DEPENDENCY, help_msg, { stack = job }))
    end

    -- Start the job (uv.spawn might fail)
    local spawn_ok, err = pcall(job.start, job)
    if not spawn_ok then
        -- Handle spawn error
        return _on_setup_failed(
            Error(
                "SETUP",
                Error.Types.SETUP.MISSING_DEPENDENCY,
                "Failed to spawn mcp-hub process: " .. tostring(err) .. "\n\n" .. help_msg
            )
        )
    end

    return State.hub_instance
end

return M
