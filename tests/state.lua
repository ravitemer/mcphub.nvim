return {
    ---@type "not_started" | "in_progress" | "completed" | "failed" MCPHub setup state
    setup_state = "completed",
    ---@type MCPHub.Config
    config = {},
    ---@type table<string, MCPServerConfig>
    servers_config = {},
    ---@type table<string, NativeMCPServerConfig>
    native_servers_config = {},

    ---@type MCPHub.Hub?
    hub_instance = nil,
    ---@type MCPHub.UI?
    ui_instance = nil,

    -- Marketplace state
    marketplace_state = {
        ---@type "empty" | "loading" | "loaded" | "error"
        status = "empty",
        catalog = {
            ---@type MarketplaceItem[]
            items = {},
            ---@type number
            last_updated = nil,
        },
        filters = {
            search = "",
            category = "",
            sort = "stars", -- newest/stars/name
        },
        ---@type MarketplaceItem
        selected_server = nil,
        ---@type table<string, {data: table,timestamp: number}>
        server_details = {}, -- Map of mcpId -> details
    },

    -- Server state
    server_state = {
        ---@type MCPHub.Constants.HubState
        state = "ready",
        ---@type number?
        pid = nil, -- Server process ID when running
        ---@type number?
        started_at = nil, -- When server was started
        ---@type MCPServer[]
        servers = require("tests.stubs.servers"), -- Regular MCP servers
        ---@type NativeServer[]
        native_servers = require("tests.stubs.native_servers"), -- Native MCP servers
    },

    -- Error management
    errors = {
        ---@type MCPError[]
        items = {}, -- Array of error objects with type property
    },

    -- Server output
    server_output = {
        ---@type LogEntry[]
        entries = {}, -- Chronological server output entries
    },

    -- State management
    last_update = 0,
    subscribers = {
        ui = {}, -- UI-related subscribers
        server = {}, -- Server state subscribers
        all = {}, -- All state changes subscribers
        errors = {},
    },

    -- subscribers
    ---@type table<string, function[]>
    event_subscribers = {},
}
