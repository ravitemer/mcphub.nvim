local State = require("mcphub.state")

---@class NativeServer
---@field name string Server name
---@field displayName string Display name
---@field status string Server status (connected|disconnected|disabled)
---@field error string|nil Error message if any
---@field capabilities table Server capabilities
---@field uptime number Server uptime
---@field lastStarted string ISO timestamp of last start
local NativeServer = {}
NativeServer.__index = NativeServer

--- Create a new native server instance
---@param def table Server definition with name, capabilities etc
---@return NativeServer | nil Server instance or nil on error
function NativeServer:new(def)
    -- Validate required fields
    if not def.name then
        vim.notify("NativeServer definition must include name", vim.log.levels.ERROR)
        return
    end
    if not def.capabilities then
        vim.notify("NativeServer definition must include capabilities", vim.log.levels.ERROR)
        return
    end

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
    -- Check server state
    if self.status ~= "connected" then
        return nil, string.format("Server '%s' is not connected (status: %s)", self.name, self.status)
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
        return nil, string.format("Tool '%s' not found", name)
    end

    -- Track if tool has completed to prevent double-handling
    local tool_finished = false
    local tool_result = nil

    -- Create output handler
    local function output_handler(result)
        if tool_finished then
            vim.notify(string.format("output_handler for tool %s was called more than once", name), vim.log.levels.WARN)
            return
        end
        tool_finished = true
        if opts.callback then
            opts.callback(result)
            return
        end
        tool_result = result
        return result
    end

    -- Execute tool with output handler
    local ok, result = pcall(tool.callback, arguments, output_handler)
    if not ok then
        -- Handle pcall error
        if opts.callback then
            opts.callback(nil, result)
        end
        return nil, result
    end

    -- Handle synchronous return
    if result ~= nil then
        -- Tool returned value directly
        return output_handler(result)
    end

    -- Tool will call output_handler asynchronously
    if not opts.callback then
        -- If no callback but async, return tool result
        return tool_result, nil
    end
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
    disable = disable or true
    if disable then
        self.status = "disabled"
    else
        self.status = "disconnected"
    end
end

return NativeServer
