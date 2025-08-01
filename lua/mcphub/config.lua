local M = {}

local SHUTDOWN_DELAY = 5 * 60 * 1000 -- 5 minutes

---@class MCPHub.WorkspaceConfig
---@field enabled boolean Master switch for workspace-specific hubs
---@field look_for string[] Files to search for (in order)
---@field port_range { min: number, max: number } Port range for workspace hubs
---@field reload_on_dir_changed boolean Whether to listen to DirChanged events to reload workspace config
---@field get_port fun(): number | nil Function that determines that returns the port

---@class MCPHub.Config
local defaults = {
    port = 37373, -- Default port for MCP Hub
    server_url = nil, -- In cases where mcp-hub is hosted somewhere, set this to the server URL e.g `http://mydomain.com:customport` or `https://url_without_need_for_port.com`
    config = vim.fn.expand("~/.config/mcphub/servers.json"), -- Default config location
    shutdown_delay = SHUTDOWN_DELAY, -- Delay before shutting down the mcp-hub
    mcp_request_timeout = 60000, --Timeout for MCP requests in milliseconds, useful for long running tasks
    ---@type table<string, NativeServerDef>
    native_servers = {},
    builtin_tools = {
        ---@type EditSessionConfig
        edit_file = {
            parser = {
                track_issues = true,
                extract_inline_content = true,
            },
            locator = {
                fuzzy_threshold = 0.8,
                enable_fuzzy_matching = true,
            },
            ui = {
                go_to_origin_on_complete = true,
                keybindings = {
                    accept = ".", -- Accept current change
                    reject = ",", -- Reject current change
                    next = "n", -- Next diff
                    prev = "p", -- Previous diff
                    accept_all = "ga", -- Accept all remaining changes
                    reject_all = "gr", -- Reject all remaining changes
                },
            },
            feedback = {
                include_parser_feedback = true,
                include_locator_feedback = true,
                include_ui_summary = true,
                ui = {
                    include_session_summary = true,
                    include_final_diff = true,
                    send_diagnostics = true,
                    wait_for_diagnostics = 500,
                    diagnostic_severity = vim.diagnostic.severity.WARN, -- Only show warnings and above by default
                },
            },
        },
    },
    --- Custom function to parse json file (e.g `require'json5'.parse` from `https://github.com/Joakker/lua-json5 to parse json5 syntax for .vscode/mcp.json like files)
    ---@type function | nil
    json_decode = nil,
    ---@type boolean | fun(parsed_params: MCPHub.ParsedParams): boolean | nil | string  Function to determine if a call should be auto-approved
    auto_approve = false,
    auto_toggle_mcp_servers = true, -- Let LLMs start and stop MCP servers automatically
    use_bundled_binary = false, -- Whether to use bundled mcp-hub binary
    ---@type table | fun(context: MCPHub.JobContext): table Global environment variables available to all MCP servers
    global_env = {}, -- Environment variables that will be available to all MCP servers
    ---@type string?
    cmd = nil, -- will be set based on system if not provided
    ---@type table?
    cmdArgs = nil, -- will be set based on system if not provided
    ---@type LogConfig
    log = {
        level = vim.log.levels.ERROR,
        to_file = false,
        file_path = nil,
        prefix = "MCPHub",
    },
    ---@type MCPHub.UIConfig
    ui = {
        window = {},
        wo = {},
    },
    ---@type MCPHub.Extensions.Config
    extensions = {
        avante = {
            enabled = true,
            make_slash_commands = true,
        },
        copilotchat = {
            enabled = true,
            convert_tools_to_functions = true,
            convert_resources_to_functions = true,
            add_mcp_prefix = false,
        },
    },
    ---@type MCPHub.WorkspaceConfig
    workspace = {
        enabled = true, -- Enables workspace-specific hubs
        look_for = { ".mcphub/servers.json", ".vscode/mcp.json", ".cursor/mcp.json" }, -- Files to search for (in order)
        reload_on_dir_changed = true, -- Whether to listen to DirChanged events to reload workspace config
        port_range = { min = 40000, max = 41000 }, -- Port range for workspace hubs
        -- function that determines that returns the port
        --- @type fun(): number | nil
        get_port = nil,
    },
    on_ready = function() end,
    ---@param msg string
    on_error = function(msg) end,
}

---@param opts MCPHub.Config?
---@return MCPHub.Config
function M.setup(opts)
    M.config = vim.tbl_deep_extend("force", defaults, opts or {})
    return M.config
end

return setmetatable(M, {
    __index = function(_, key)
        if key == "setup" then
            return M.setup
        end
        return rawget(M.config, key)
    end,
})
