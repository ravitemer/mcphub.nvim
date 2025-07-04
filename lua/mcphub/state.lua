---[[
--- Global state management for MCPHub
--- Handles setup, server, and UI state
---]]
local constants = require("mcphub.utils.constants")
local log = require("mcphub.utils.log")

---@class MCPHub.State
local State = {
    ---@type "not_started" | "in_progress" | "completed" | "failed" MCPHub setup state
    setup_state = "not_started",
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
        state = constants.HubState.STARTING,
        ---@type number?
        pid = nil, -- Server process ID when running
        ---@type number?
        started_at = nil, -- When server was started
        ---@type MCPServer[]
        servers = {}, -- Regular MCP servers
        ---@type NativeServer[]
        native_servers = {}, -- Native MCP servers
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

---@return boolean
function State:is_connected()
    return self.server_state.state == constants.HubState.READY
        or self.server_state.state == constants.HubState.RESTARTED
end

function State:reset()
    State.server_state = {
        status = "disconnected",
        pid = nil,
        started_at = nil,
        servers = {},
        native_servers = State.server_state.native_servers or {},
    }
    State.errors = {
        items = {},
    }
    State.server_output = {
        entries = {},
    }
    State.marketplace_state = {
        status = "loading",
        catalog = {
            items = {},
            last_updated = nil,
        },
        filters = {
            search = "",
            category = "",
            sort = "stars",
        },
        selected_server = nil,
        server_details = {},
    }
    State.last_update = 0
end

---@param partial_state table
---@param update_type? string
function State:update(partial_state, update_type)
    update_type = update_type or "all"
    local changes = {}

    -- Track changes
    for k, v in pairs(partial_state) do
        if type(v) == "table" then
            if not vim.deep_equal(self[k], v) then
                changes[k] = true
                self[k] = vim.tbl_deep_extend("force", self[k] or {}, v)
            end
        else
            if self[k] ~= v then
                changes[k] = true
                self[k] = v
            end
        end
    end

    -- Notify if changed
    if next(changes) then
        self.last_update = vim.loop.now()
        self:notify_subscribers(changes, update_type)
    end
end

--- Add an error to state and optionally log it
---@param err MCPError The error to add
---@param log_level? string Optional explicit log level (debug/info/warn/error)
function State:add_error(err, log_level)
    -- Add error to list
    table.insert(self.errors.items, err)

    -- Sort errors with newest first
    table.sort(self.errors.items, function(a, b)
        return (a.timestamp or 0) > (b.timestamp or 0)
    end)

    -- Keep reasonable history (max 100 errors)
    if #self.errors.items > 100 then
        table.remove(self.errors.items)
    end

    -- Notify subscribers
    self:notify_subscribers({
        errors = true,
    }, "errors")

    -- Log with explicit level or infer from error type
    if log_level then
        log[log_level:lower()](tostring(err))
    else
        -- Default logging behavior based on error type
        local level = err.type == "SETUP" and "error" or err.type == "SERVER" and "warn" or "info"
        log[level](tostring(err))
    end
end

--- Clear errors of a specific type or all errors
---@param type? string Optional error type to clear (setup/server/runtime)
function State:clear_errors(type)
    if type then
        -- Filter out errors of specified type
        local filtered = {}
        for _, err in ipairs(self.errors.items) do
            if err.type:lower() ~= type:lower() then
                table.insert(filtered, err)
            end
        end
        self.errors.items = filtered
    else
        -- Clear all errors
        self.errors.items = {}
    end
    self:notify_subscribers({
        errors = true,
    }, "errors")
end

--- Get all errors of a specific type
---@param type? string Optional error type (setup/server/runtime)
---@return MCPError[]
function State:get_errors(type)
    if type then
        -- Filter by type
        local filtered = {}
        for _, err in ipairs(self.errors.items) do
            if err.type:lower() == type:lower() then
                table.insert(filtered, err)
            end
        end
        return vim.deepcopy(filtered)
    end
    return vim.deepcopy(self.errors.items)
end
--- Check if a server is installed by comparing id
--- @param id string Server ID to check
--- @return boolean true if server is installed
function State:is_server_installed(id)
    local servers = self.server_state.servers or {}
    for _, server in ipairs(servers) do
        if server.name == id then
            return true
        end
    end
    return false
end

---@param event string
---@param data any
function State:emit(event, data)
    local event_subscribers = self.event_subscribers[event]
    if event_subscribers then
        for _, cb in ipairs(event_subscribers) do
            cb(data)
        end
    end
end

---@param event string
---@param callback function
function State:add_event_listener(event, callback)
    self.event_subscribers[event] = self.event_subscribers[event] or {}
    table.insert(self.event_subscribers[event], callback)
end

---@param event string
---@param callback function
function State:remove_event_listener(event, callback)
    if self.event_subscribers[event] then
        for i, cb in ipairs(self.event_subscribers[event]) do
            if cb == callback then
                table.remove(self.event_subscribers[event], i)
                break
            end
        end
    end
end

---@param event string
function State:remove_all_event_listeners(event)
    self.event_subscribers[event] = {}
end

---@param entry LogEntry
function State:add_server_output(entry)
    if not entry or not entry.type or not entry.message then
        return
    end

    -- Ensure entry has timestamp
    entry.timestamp = entry.timestamp or vim.loop.now()

    table.insert(self.server_output.entries, {
        type = entry.type, -- info/warn/error/debug
        message = entry.message, -- The actual message
        timestamp = entry.timestamp,
        data = entry.data, -- Optional extra data
    })

    -- Keep reasonable history
    if #self.server_output.entries > 1000 then
        table.remove(self.server_output.entries, 1)
    end

    self:notify_subscribers({
        logs = true,
    }, "logs")
end

---@param status string
---@param ... any
function State:update_hub_state(status, ...)
    self:update({
        server_state = {
            state = status,
            unpack(... or {}),
        },
    }, "server")
end

---@param callback function
---@param types string[]
function State:subscribe(callback, types)
    types = types or { "all" }
    for _, type in ipairs(types) do
        self.subscribers[type] = self.subscribers[type] or {}
        table.insert(self.subscribers[type], callback)
    end
end

---@param changes table
---@param update_type string
function State:notify_subscribers(changes, update_type)
    -- Notify type-specific subscribers
    if update_type ~= "all" and self.subscribers[update_type] then
        for _, callback in ipairs(self.subscribers[update_type]) do
            callback(self, changes)
        end
    end
    -- Always notify 'all' subscribers
    for _, callback in ipairs(self.subscribers.all) do
        callback(self, changes)
    end
end

return State
