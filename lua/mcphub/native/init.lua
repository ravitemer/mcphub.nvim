local NativeServer = require("mcphub.native.server")
local State = require("mcphub.state")

---@class NativeManager
local Native = {}

--- Register a native server definition
---@param def table Server definition with name, capabilities etc
function Native.register(def)
    -- Create server instance
    local server = NativeServer:new(def)
    if not server then
        return
    end
    -- Update server state with server instance state
    table.insert(State.server_state.native_servers, server)
end

--- Update native server config
---@param name string Server name
---@param config table Configuration updates
function Native.update_config(name, config)
    -- Update config for specific server
    local updated_config = vim.deepcopy(State.native_server_config)
    updated_config[name] = vim.tbl_deep_extend("force", updated_config[name] or {}, config)

    State:update({
        native_server_config = updated_config,
    }, "server")
end

return Native
