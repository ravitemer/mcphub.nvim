local NativeServer = require("mcphub.native.utils.server")
local State = require("mcphub.state")
local log = require("mcphub.utils.log")

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
-- - native_servers: Table of native MCP server definitions
-- {
--     ["server-name"] = {
--         name = "server-name",
--         displayName = "Display Name", -- Optional
--         capabilities = {
--             tools = {
--                 {
--                     name = "tool-name",
--                     description = "Tool description",
--                     inputSchema = {...}, -- JSON Schema
--                     handler = function(args) ... end
--                 }
--             }, -- Optional tool definitions
--             resources = {...}, -- Optional resource definitions
--             resourceTemplates = {...} -- Optional resource template definitions
--         }
--     }
-- }

--- Register a native server definition
---@param def table Server definition with name capabilities etc
function Native.register(def)
    -- Create server instance
    local server = NativeServer:new(def)
    if not server then
        log.error({
            code = "NATIVE_REGISTER_FAILED",
            message = "Failed to create native server instance",
            data = { name = def.name },
        })
        return
    end

    -- Update server state with server instance state
    table.insert(State.server_state.native_servers, server)
end

return Native
