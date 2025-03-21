local Error = require("mcphub.errors")
local ImageCache = require("mcphub.utils.image_cache")
local Job = require("plenary.job")
local MCPHub = require("mcphub.hub")
local State = require("mcphub.state")
local log = require("mcphub.utils.log")
local validation = require("mcphub.validation")
local version = require("mcphub.version")

local M = {}

--- Setup MCPHub plugin with error handling and validation
--- @param opts? { port?: number, config?: string, log?: table, on_ready?: fun(hub: MCPHub), on_error?: fun(err: string) }
--[[
Setup options:
- port: Port for MCP Hub server (default: auto-select)
- config: Path to server config file (default: ~/.config/mcp/servers.json)
- log: Logging configuration
  - level: Minimum log level (default: ERROR)
  - to_file: Whether to log to file (default: false)
  - file_path: Path to log file (default: nil)
  - prefix: Prefix for log messages (default: MCPHub)
- on_ready: Callback when server is ready(hub: MCPHub)
- on_error: Callback for setup errors(err: string)
--]]
function M.setup(opts)
    -- Return if already setup or in progress
    if State.setup_state ~= "not_started" then
        return State.hub_instance
    end

    -- Update state to in_progress
    State:update({
        setup_state = "in_progress",
    }, "setup")

    -- Set default options
    local config = vim.tbl_deep_extend("force", {
        port = nil,
        config = nil,
        log = {
            level = vim.log.levels.ERROR,
            to_file = false,
            file_path = nil,
            prefix = "MCPHub",
        },
        on_ready = function() end,
        on_error = function() end,
    }, opts or {})

    -- Set up logging first
    log.setup(config.log or {})

    -- Create UI instance early
    State.ui_instance = require("mcphub.ui"):new()
    State.config = config

    -- Create command early
    vim.api.nvim_create_user_command("MCPHub", function()
        if State.ui_instance then
            State.ui_instance:toggle()
        else
            State:add_error(Error("RUNTIME", Error.Types.RUNTIME.INVALID_STATE, "UI not initialized"))
        end
    end, {
        desc = "Toggle MCP Hub window",
    })

    -- Validate options
    local validation_result = validation.validate_setup_opts(config)
    if not validation_result.ok then
        local err = validation_result.error
        -- Add error to state and invoke error callback
        State:add_error(err)
        State:update({
            setup_state = "failed",
        }, "setup")
        config.on_error(tostring(err))
        return nil
    end

    -- Update servers config in state
    local file_result = validation.validate_config_file(config.config)
    if file_result.ok and file_result.json then
        State.servers_config = file_result.json.mcpServers
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

    -- Get mcp-hub path from utils
    local node_bin = require("mcphub.utils").get_bundled_mcp_path()

    -- Start version check
    Job:new({
        command = node_bin,
        args = { "--version" },
        on_exit = vim.schedule_wrap(function(j, code)
            if code ~= 0 then
                local err = Error(
                    "SETUP",
                    Error.Types.SETUP.MISSING_DEPENDENCY,
                    "mcp-hub not found. Update the plugin and make sure build = 'build.lua' is in your config"
                )
                State:add_error(err)
                State:update({
                    setup_state = "failed",
                }, "setup")
                config.on_error(tostring(err))
                return
            end

            -- Validate version
            local version_result = validation.validate_version(j:result()[1])
            if not version_result.ok then
                State:add_error(version_result.error)
                State:update({
                    setup_state = "failed",
                }, "setup")
                config.on_error(tostring(version_result.error))
                return
            end

            -- Create hub instance
            local hub = MCPHub:new(config)
            if not hub then
                local err = Error("SETUP", Error.Types.SETUP.SERVER_START, "Failed to create MCPHub instance")
                State:add_error(err)
                State:update({
                    setup_state = "failed",
                }, "setup")
                config.on_error(tostring(err))
                return
            end

            -- Store hub instance with direct assignment to preserve metatable
            State.setup_state = "completed"
            State.hub_instance = hub
            State:notify_subscribers({
                setup_state = true,
                hub_instance = true,
            }, "setup")

            -- Initialize image cache
            ImageCache.setup()

            -- Start hub
            hub:start({
                on_ready = config.on_ready,
                on_error = config.on_error,
            })
        end),
    }):start()

    return State.hub_instance
end

function M.on(event, callback)
    State:add_event_listener(event, callback)
end

function M.off(event, callback)
    State:remove_event_listener(event, callback)
end

function M.get_hub_instance()
    if State.setup_state ~= "completed" then
        return nil
    end
    return State.hub_instance
end

function M.get_state()
    return State
end

return M
