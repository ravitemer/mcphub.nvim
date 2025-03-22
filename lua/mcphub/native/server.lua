local State = require("mcphub.state")
local log = require("mcphub.utils.log")

---@class NativeServer
---@field name string Server name
---@field displayName string Display name
---@field status string Server status (connected|disconnected|disabled)
---@field error string|nil Error message if any
---@field capabilities table Server capabilities
---@field uptime number Server uptime
---@field lastStarted number Last started timestamp
local NativeServer = {}
NativeServer.__index = NativeServer

-- Helper function to find matching resource
function NativeServer:find_matching_resource(uri)
    -- Check direct resources first
    for _, resource in ipairs(self.capabilities.resources) do
        if resource.uri == uri then
            log.debug(string.format("Matched uri"))
            return resource
        end
    end

    -- Check templates
    for _, template in ipairs(self.capabilities.resourceTemplates) do
        -- Pattern match uri against template
        log.debug(string.format("Matching uri '%s' against template '%s'", uri, template.uriTemplate))
        if uri:match(template.uriTemplate) then
            log.debug(string.format("Matched uri template"))
            return template
        end
    end

    return nil
end

--- Create a new native server instance
---@param def table Server definition with name capabilities etc
---@return NativeServer | nil Server instance or nil on error
function NativeServer:new(def)
    -- Validate required fields
    -- Validate required fields
    if not def.name then
        log.warn("NativeServer definition must include name")
        return
    end
    if not def.capabilities then
        log.warn("NativeServer definition must include capabilities")
        return
    end

    log.debug({
        code = "NATIVE_SERVER_INIT",
        message = "Creating new native server",
        data = { name = def.name, capabilities = def.capabilities },
    })

    local instance = {
        name = def.name,
        displayName = def.displayName or def.name,
        status = "connected",
        error = nil,
        capabilities = {
            tools = {},
            resources = {},
            resourceTemplates = {},
        },
        uptime = 0,
        lastStarted = os.time(),
    }
    setmetatable(instance, self)

    -- Initialize capabilities
    instance:initialize(def)

    return instance
end

--- Initialize or reinitialize server capabilities
---@param def table Server definition
function NativeServer:initialize(def)
    -- Reset error state
    self.error = nil
    self.capabilities = {
        tools = def.capabilities.tools or {},
        resources = def.capabilities.resources or {},
        resourceTemplates = def.capabilities.resourceTemplates or {},
    }

    -- Get server config
    local server_config = State.native_servers_config[self.name] or {}
    -- Check if server is disabled
    if server_config.disabled then
        self.status = "disabled"
        return
    end
    self.status = "connected"
    self.lastStarted = os.time()
end

--- Execute a tool by name
---@param name string Tool name to execute
---@param arguments table Arguments for the tool
---@return table|nil result Tool execution result
---@return string|nil error Error message if any
function NativeServer:call_tool(name, arguments, opts)
    opts = opts or {}
    -- Create output handler
    -- Track if tool has completed to prevent double-handling
    local tool_finished = false
    local function output_handler(result, err)
        if tool_finished then
            return
        end
        tool_finished = true
        if opts.callback then
            opts.callback(result, err)
            return
        end
        return result, err
    end
    log.debug(string.format("Calling tool '%s' on server '%s'", name, self.name))
    -- Check server state
    if self.status ~= "connected" then
        local err = string.format("Server '%s' is not connected (status: %s)", self.name, self.status)
        log.warn(string.format("Server '%s' is not connected (status: %s)", self.name, self.status))
        return output_handler(nil, err)
    end

    -- Find tool in capabilities
    local tool
    for _, t in ipairs(self.capabilities.tools) do
        if t.name == name then
            tool = t
            break
        end
    end
    if not tool then
        local err = string.format("Tool '%s' not found", name)
        log.warn(string.format("Tool '%s' not found", name))
        return output_handler(nil, err)
    end

    -- Execute tool with output handler
    local ok, result = pcall(tool.handler, arguments, output_handler)
    if not ok then
        log.warn(string.format("Tool execution failed: %s", result))
        return output_handler(nil, result)
    end

    -- Handle synchronous return
    if result ~= nil then
        -- Tool returned value directly
        return output_handler(result)
    end
    return output_handler(nil)
end

function NativeServer:access_resource(uri, opts)
    opts = opts or {}
    -- Create output handler
    -- Track if resource has called to prevent double-handling
    local resource_finished = false
    local function output_handler(result, err)
        if resource_finished then
            return
        end
        resource_finished = true
        if opts.callback then
            opts.callback(result, err)
            return
        end
        return result, err
    end
    -- Check server state
    if self.status ~= "connected" then
        return output_handler(nil, string.format("Server '%s' is not connected (status: %s)", self.name, self.status))
    end

    log.debug(string.format("Accessing resource '%s' on server '%s'", uri, self.name))
    -- Find matching resource/template
    local resource = self:find_matching_resource(uri)
    if not resource then
        local err = string.format("Resource '%s' not found", uri)
        log.warn(string.format("Resource '%s' not found", uri))
        return output_handler(nil, err)
    end

    -- Check if resource has handler
    if not resource.handler then
        local err = "Resource has no handler"
        log.warn(string.format("Resource '%s' has no handler", uri))
        return output_handler(nil, err)
    end

    -- Call resource handler
    local ok, result = pcall(resource.handler, uri, output_handler)
    if not ok then
        log.warn(string.format("Resource access failed: %s", result))
        return output_handler(nil, result)
    end

    -- Handle synchronous return
    if result ~= nil then
        -- Handler returned value directly
        return output_handler(result)
    end
    return output_handler(nil)
end

function NativeServer:start()
    -- Check server state
    if self.status == "connected" then
        return true
    end
    self.status = "connected"
    self.lastStarted = os.time()
    return true
end

function NativeServer:stop(disable)
    disable = disable or false
    if disable then
        self.status = "disabled"
    else
        self.status = "disconnected"
    end
end

return NativeServer
