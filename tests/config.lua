---@class MCPHub.Config
return {
    port = 37373, -- Default port for MCP Hub
    server_url = nil, -- In cases where mcp-hub is hosted somewhere, set this to the server URL e.g `http://mydomain.com:customport` or `https://url_without_need_for_port.com`
    config = vim.fn.fnamemodify("tests/servers.json", ":p"), -- Default config location
    shutdown_delay = 600000, -- Delay before shutting down the mcp-hub
    mcp_request_timeout = 60000, --Timeout for MCP requests in milliseconds, useful for long running tasks
    ---@type table<string, NativeServerDef>
    native_servers = {},
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
        window = {
            width = 0.85, -- 0-1 (ratio); "50%" (percentage); 50 (raw number)
            height = 0.85, -- 0-1 (ratio); "50%" (percentage); 50 (raw number)
            align = "center", -- "center", "top-left", "top-right", "bottom-left", "bottom-right", "top", "bottom", "left", "right"
            border = "rounded", -- "none", "single", "double", "rounded", "solid", "shadow"
            relative = "editor",
            zindex = 50,
        },
        wo = { -- window-scoped options (vim.wo)
            winhl = "Normal:MCPHubNormal,FloatBorder:MCPHubBorder",
        },
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
