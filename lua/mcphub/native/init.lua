local NativeServer = require("mcphub.native.server")
local State = require("mcphub.state")

---@class NativeManager
local Native = {}

--- Check if a server name belongs to a native server
---@param server_name string Name of the server to check
---@return boolean true if server is native
function Native.is_native_server(server_name)
    for _, server in ipairs(State.server_state.native_servers) do
        if server.name == server_name then
            return server
        end
    end
    return false
end

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

return Native
