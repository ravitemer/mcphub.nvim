---@class Native
---@field is_native_server fun(server_name: string): NativeServer|nil Check if a server name belongs to a native server
---@field add_server fun(server_name: string, def?: table): NativeServer|nil Add new native server
---@field add_tool fun(server_name: string, tool_def: MCPTool): NativeServer|nil Add tool to server
---@field add_resource fun(server_name: string, resource_def: MCPResource): NativeServer|nil Add resource to server
---@field add_resource_template fun(server_name: string, template_def: MCPResourceTemplate): NativeServer|nil Add template to server

local Error = require("mcphub.utils.errors")
local NativeServer = require("mcphub.native.utils.server")
local State = require("mcphub.state")
local log = require("mcphub.utils.log")
local validate = require("mcphub.utils.validation")

---@class NativeManager
local Native = {}

--- Check if a server name belongs to a native server
---@param server_name string Name of the server to check
---@return NativeServer|nil server instance if found
function Native.is_native_server(server_name)
    for _, server in ipairs(State.server_state.native_servers) do
        if server.name == server_name then
            return server
        end
    end
    return false
end

local function handle_error(err)
    State:add_error(err)
end

--- Internal: Register a native server definition
---@private
---@param def table Server definition with name capabilities etc
---@return NativeServer|nil server Server instance or nil on error
function Native.register(def)
    if type(def) ~= "table" then
        handle_error(Error("VALIDATION", Error.Types.NATIVE.INVALID_SCHEMA, "Server definition is not a table"))
        return nil
    end
    local existing = Native.is_native_server(def.name)
    if existing then
        State:add_error(
            Error("VALIDATION", Error.Types.NATIVE.INVALID_SCHEMA, string.format("%s already exists", def.name))
        )
        return existing
    end
    local result = validate.validate_native_server(def)
    if not result.ok then
        handle_error(result.error)
        return nil
    end
    -- Create server instance
    local server = NativeServer:new(def)
    if not server then
        handle_error("Failed to create native server instance")
        return nil
    end

    -- Update server state with server instance state
    table.insert(State.server_state.native_servers, server)
    return server
end

--API

--- Add a new native server
---@param server_name string Name of the server
---@param def? { displayName?: string, capabilities?: MCPCapabilities } Optional server definition overrides
---@return NativeServer|nil server Server instance or nil on error
function Native.add_server(server_name, def)
    -- Check if server already exists
    local existing = Native.is_native_server(server_name)
    if existing then
        State:add_error(
            Error("VALIDATION", Error.Types.NATIVE.INVALID_SCHEMA, string.format("%s already exists", server_name))
        )
        return existing
    end

    -- Create default server definition
    local server_def = vim.tbl_deep_extend("force", {
        name = server_name,
        displayName = server_name,
        capabilities = {
            tools = {},
            resources = {},
            resourceTemplates = {},
        },
    }, def or {})
    --make sure the server name is same as the key
    server_def.name = server_name

    -- Register the server
    return Native.register(server_def)
end

--- Add a tool to a server, creating the server if it doesn't exist
---@param server_name string Name of the server
---@param tool_def MCPTool Tool definition including name, description, and handler
---@return NativeServer|nil server The server instance or nil on error
function Native.add_tool(server_name, tool_def)
    local result = validate.validate_tool(tool_def)
    if not result.ok then
        handle_error(result.error)
        return nil
    end

    local server = Native.is_native_server(server_name)
    if server then
        table.insert(server.capabilities.tools, tool_def)
        return server
    else
        return Native.add_server(server_name, {
            capabilities = { tools = { tool_def } },
        })
    end
end

--- Add a resource to a server, creating the server if it doesn't exist
---@param server_name string Name of the server
---@param resource_def MCPResource Resource definition including URI and handler
---@return NativeServer|nil server The server instance or nil on error
function Native.add_resource(server_name, resource_def)
    local result = validate.validate_resource(resource_def)
    if not result.ok then
        handle_error(result.error)
        return nil
    end

    local server = Native.is_native_server(server_name)
    if server then
        table.insert(server.capabilities.resources, resource_def)
        return server
    else
        return Native.add_server(server_name, {
            capabilities = { resources = { resource_def } },
        })
    end
end

--- Add a resource template to a server, creating the server if it doesn't exist
---@param server_name string Name of the server
---@param template_def MCPResourceTemplate Template definition including URI template and handler
---@return NativeServer|nil server The server instance or nil on error
function Native.add_resource_template(server_name, template_def)
    local result = validate.validate_resource_template(template_def)
    if not result.ok then
        handle_error(result.error)
        return nil
    end

    local server = Native.is_native_server(server_name)
    if server then
        table.insert(server.capabilities.resourceTemplates, template_def)
        return server
    else
        return Native.add_server(server_name, {
            capabilities = { resourceTemplates = { template_def } },
        })
    end
end

function Native.setup()
    require("mcphub.native.neovim")
end

return Native
