local M = {}

local SHUTDOWN_DELAY = 10 * 60 * 1000 -- 10 minutes

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
        replace_in_file = {
            keymaps = {
                accept = "ga",
                reject = "gr",
            },
        },
    },
    auto_approve = false,
    auto_toggle_mcp_servers = true, -- Let LLMs start and stop MCP servers automatically
    use_bundled_binary = false, -- Whether to use bundled mcp-hub binary
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
    extensions = {
        ---@type MCPHubAvanteConfig
        avante = {
            enabled = true,
            make_slash_commands = true,
        },
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
