local M = {}

---@enum MCPHub.Constants.ConnectionStatus
M.ConnectionStatus = {
    CONNECTED = "connected",
    CONNECTING = "connecting",
    DISCONNECTED = "disconnected",
    DISCONNECTING = "disconnecting",
    UNAUTHORIZED = "unauthorized",
    DISABLED = "disabled",
}

---@enum MCPHub.Constants.EventTypes
M.EventTypes = {
    HEARTBEAT = "heartbeat",
    HUB_STATE = "hub_state",
    LOG = "log",
    SUBSCRIPTION_EVENT = "subscription_event",
}

---@enum MCPHub.Constants.SubscriptionTypes
M.SubscriptionTypes = {
    TOOL_LIST_CHANGED = "tool_list_changed",
    RESOURCE_LIST_CHANGED = "resource_list_changed",
    PROMPT_LIST_CHANGED = "prompt_list_changed",

    CONFIG_CHANGED = "config_changed",
    SERVERS_UPDATING = "servers_updating",
    SERVERS_UPDATED = "servers_updated",

    WORKSPACES_UPDATED = "workspaces_updated",
}

---@enum MCPHub.Constants.HubState
M.HubState = {
    STARTING = "starting",
    READY = "ready",
    CONFIGURING = "configuring",
    ERROR = "error",
    RESTARTING = "restarting",
    RESTARTED = "restarted",
    STOPPED = "stopped",
    STOPPING = "stopping",
}

return M
