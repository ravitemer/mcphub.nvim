local Error = require("mcphub.utils.errors")
local ImageCache = require("mcphub.utils.image_cache")
local Job = require("plenary.job")
local MCPHub = require("mcphub.hub")
local State = require("mcphub.state")
local log = require("mcphub.utils.log")
local native = require("mcphub.native")
local utils = require("mcphub.utils")
local validation = require("mcphub.utils.validation")
local version = require("mcphub.utils.version")

local M = {
    is_native_server = native.is_native_server,
    add_server = native.add_server,
    add_tool = native.add_tool,
    add_resource = native.add_resource,
    add_resource_template = native.add_resource_template,
}

--- Setup MCPHub plugin with error handling and validation
--- @param opts? { port?: number, cmd?: string, native_servers? : table, cmdArgs?: table, config?: string, log?: table, on_ready?: fun(hub: MCPHub), on_error?: fun(err: string) }
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
        port = 37373, -- Default port for MCP Hub
        config = vim.fn.expand("~/.config/mcphub/servers.json"), -- Default config location
        native_servers = {},
        use_bundled_binary = false, -- Whether to use bundled mcp-hub binary
        cmd = "mcp-hub",
        cmdArgs = {},
        log = {
            level = vim.log.levels.ERROR,
            to_file = false,
            file_path = nil,
            prefix = "MCPHub",
        },
        -- Default window settings
        ui = {
            window = {
                width = 0.85, -- 0-1 (ratio); "50%" (percentage); 50 (raw number)
                height = 0.85, -- 0-1 (ratio); "50%" (percentage); 50 (raw number)
                border = "rounded", -- "none", "single", "double", "rounded", "solid", "shadow"
                relative = "editor",
                zindex = 50,
            },
        },
        extensions = {
            codecompanion = {
                show_result_in_chat = true,
                make_vars = true,
            },
            avante = {
                auto_approve_mcp_tool_calls = false,
            },
        },
        on_ready = function() end,
        on_error = function() end,
    }, opts or {})

    -- Override cmd if using bundled binary
    if config.use_bundled_binary then
        config.cmd = utils.get_bundled_mcp_path()
    end

    -- Set up logging first
    log.setup(config.log or {})

    -- Create UI instance early
    State.ui_instance = require("mcphub.ui"):new(config.ui)
    State.config = config

    -- Create command early
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
        State.native_servers_config = file_result.json.nativeMCPServers or {}
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
        return Job:new({
            command = config.cmd,
            args = utils.clean_args({ config.cmdArgs, "--version" }),
            on_exit = vim.schedule_wrap(function(j, code)
                M._handle_version_check(j, code, config)
            end),
        })
    end)

    if not ok then
        -- Handle executable not found error
        local msg = [[mcp-hub executable not found. Please ensure:
1. For global install: Run 'npm install -g mcp-hub@latest'
2. For bundled install: Set build = 'bundled_build.lua' and use_bundled_binary = true
3. For custom install: Verify cmd/cmdArgs point to valid mcp-hub executable
]]
        local err = Error("SETUP", Error.Types.SETUP.MISSING_DEPENDENCY, msg, { stack = job })
        State:add_error(err)
        State:update({
            setup_state = "failed",
        }, "setup")
        config.on_error(tostring(err))
        return nil
    end

    -- Start the job
    job:start()

    return State.hub_instance
end

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

-- Version check handler
function M._handle_version_check(j, code, config)
    if code ~= 0 then
        local err = Error(
            "SETUP",
            Error.Types.SETUP.MISSING_DEPENDENCY,
            "mcp-hub exited with non-zero code. Please verify your installation."
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

    require("mcphub.extensions").setup("codecompanion", config.extensions.codecompanion)
    --TODO: Add Support for Avante

    -- Start hub
    hub:start({
        on_ready = config.on_ready,
        on_error = config.on_error,
    })
end

return M
