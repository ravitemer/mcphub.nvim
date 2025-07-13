local Request = require("mcphub.native.utils.request")
local Response = require("mcphub.native.utils.response")
local State = require("mcphub.state")
local buf_utils = require("mcphub.native.neovim.utils.buffer")
local log = require("mcphub.utils.log")

---@class MCPTool
---@field name string Tool identifier
---@field description string|fun():string Tool description or function returning description
---@field inputSchema? table|fun():table JSON Schema for input validation or function returning schema
---@field handler fun(req: ToolRequest, res: ToolResponse): nil | table Tool handler function

---@class MCPResource
---@field name? string Resource identifier
---@field description? string|fun():string Resource description or function returning description
---@field mimeType? string Resource MIME type (e.g., "text/plain")
---@field uri string Static URI (e.g., "system://info")
---@field handler fun(req: ResourceRequest, res: ResourceResponse): nil | table Resource handler function

---@class MCPPromptArgument
---@field name string Argument name
---@field description? string Argument description
---@field required? boolean Whether the argument is required
---@field default? string Default value for the argument

---@class MCPPrompt
---@field name? string Prompt identifier
---@field description? string|fun():string Prompt description or function returning description
---@field arguments? MCPPromptArgument[]|fun():MCPPromptArgument[] List of arguments
---@field handler? fun(req: PromptRequest, res: PromptResponse): nil | table

---@class MCPResourceTemplate
---@field name? string Template identifier
---@field description? string|fun():string Template description or function returning description
---@field mimeType? string Template MIME type (e.g., "text/plain")
---@field uriTemplate string URI with parameters (e.g., "buffer://{bufnr}/lines")
---@field handler fun(req: ResourceRequest, res: ResourceResponse): nil | table Template handler function

---@class MCPCapabilities
---@field tools? MCPTool[] List of tools
---@field resources? MCPResource[] List of resources
---@field resourceTemplates? MCPResourceTemplate[] List of resource templates
---@field prompts? MCPPrompt[] List of prompts

---@class NativeServer
---@field name string Server name
---@field displayName? string Display name
---@field description? string Server description
---@field status string Server status (connected|disconnected|disabled)
---@field error? string|nil Error message if any
---@field capabilities MCPCapabilities Server capabilities
---@field uptime? number Server uptime
---@field lastStarted? number Last started timestamp
---@field config_source string Include which config file this server came from
---@field is_native boolean Flag to indicate this is a native server
local NativeServer = {}
NativeServer.__index = NativeServer

local TIMEOUT = 5 -- seconds

-- Helper function to extract params from uri using template
-- Note: Parameter values containing slashes (/) or special characters must be URL encoded
-- Example: For a template "file/read/{path}"
--   - "file/read/home%2Fuser%2Ffile.txt" ✓ (correctly encoded)
--   - "file/read/home/user/file.txt"     ✗ (will not match)

local function extract_params(uri, template)
    local params = {}

    -- Convert template into pattern with url-encoded char support
    local pattern = template:gsub("{([^}]+)}", "([^/]+)")

    -- Get param names from template
    local names = {}
    for name in template:gmatch("{([^}]+)}") do
        table.insert(names, name)
    end

    -- Match URI against pattern
    local values = { uri:match("^" .. pattern .. "$") }
    if #values == 0 then
        return nil
    end

    -- Map matched values to param names and decode them
    for i, name in ipairs(names) do
        -- URL decode the parameter value
        local decoded = values[i]:gsub("%%(%x%x)", function(hex)
            return string.char(tonumber(hex, 16))
        end)
        params[name] = decoded
    end

    return params
end

-- Helper function to find matching resource
function NativeServer:find_matching_resource(uri)
    -- Check direct resources first
    for _, resource in ipairs(self.capabilities.resources) do
        if resource.uri == uri then
            log.debug(string.format("Matched uri"))
            return resource, {}
        end
    end

    -- Check templates
    for _, template in ipairs(self.capabilities.resourceTemplates) do
        -- Extract params using template
        log.debug(string.format("Matching uri '%s' against template '%s'", uri, template.uriTemplate))
        local params = extract_params(uri, template.uriTemplate)
        if params then
            log.debug(string.format("Matched uri template with params: %s", vim.inspect(params)))
            return template, params
        end
    end

    return nil
end

--- Create a new native server instance
---@param def table Server definition with name capabilities etc
---@return NativeServer | nil Server instance or nil on error
function NativeServer:new(def)
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
        description = def.description or "",
        status = "connected",
        error = nil,
        capabilities = {
            tools = {},
            resources = {},
            resourceTemplates = {},
            prompts = {},
        },
        uptime = 0,
        lastStarted = os.time(),
        -- Always save native server settings in global config file
        config_source = State.config.config,
        is_native = true, -- Flag to indicate this is a native server
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
        prompts = def.capabilities.prompts or {},
    }

    local config_manager = require("mcphub.utils.config_manager")
    -- Get server config
    local server_config = config_manager.get_server_config(self) or {}
    -- Check if server is disabled
    if server_config.disabled then
        self.status = "disabled"
        return
    end
    self.status = "connected"
    self.lastStarted = os.time()
end

function NativeServer:get_prompt(name, arguments, opts)
    opts = opts or {}
    -- Create output handler
    local got_prompt = false
    local prompt_result, prompt_error
    local function output_handler(result, err)
        if got_prompt then
            return
        end
        prompt_result = result
        prompt_error = err
        got_prompt = true
        if opts.callback then
            opts.callback(result, err)
            return
        end
        return result, err
    end
    log.debug(string.format("Getting prompt '%s' on server '%s'", name, self.name))
    -- Check server state
    if self.status ~= "connected" then
        local err = string.format("Server '%s' is not connected (status: %s)", self.name, self.status)
        log.warn(string.format("Server '%s' is not connected (status: %s)", self.name, self.status))
        return output_handler(nil, err)
    end

    -- Find tool in capabilities
    local prompt
    for _, p in ipairs(self.capabilities.prompts) do
        if p.name == name then
            prompt = p
            break
        end
    end
    if not prompt then
        local err = string.format("Prompt '%s' not found", name)
        log.warn(string.format("Prompt '%s' not found", name))
        return output_handler(nil, err)
    end

    local editor_info = buf_utils.get_editor_info()
    -- Create req/res objects with full context
    local req = Request.PromptRequest:new({
        server = self,
        prompt = prompt,
        arguments = arguments,
        caller = opts.caller,
        editor_info = editor_info,
    })
    local res = Response.PromptResponse:new(output_handler, prompt.name, prompt.description)

    -- Execute tool with req/res
    local ok, result = pcall(prompt.handler, req, res)
    if not ok then
        log.warn(string.format("Tool execution failed: %s", result))
        return res:error(result)
    end

    -- Handle synchronous return if any
    if result ~= nil then
        return output_handler(result)
    end
    -- If native_server:get_prompt is a synchronous call but the handler didn't return anything or is running asynchronously given the res:send() arch
    -- Wait for the handler to finish until TIMEOUT as if the user didn't call res:send() this will never finish
    -- The only place the nativeserver is called synchronously is while a chat resolving  prompt
    local start_time = os.time()
    if not opts.callback then
        while not got_prompt do
            vim.wait(500)
            if os.time() - start_time > TIMEOUT then
                return output_handler(nil, "Prompt access timed out")
            end
        end
        return prompt_result, prompt_error
    end
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
    local tool_result, tool_error
    local function output_handler(result, err)
        if tool_finished then
            return
        end
        tool_result = result
        tool_error = err
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

    local editor_info = buf_utils.get_editor_info()
    -- Create req/res objects with full context
    local req = Request.ToolRequest:new({
        server = self,
        tool = tool,
        arguments = arguments,
        caller = opts.caller,
        editor_info = editor_info,
    })
    local res = Response.ToolResponse:new(output_handler)

    -- Execute tool with req/res
    local ok, result = pcall(tool.handler, req, res)
    if not ok then
        log.warn(string.format("Tool execution failed: %s", result))
        return res:error(result)
    end

    -- Handle synchronous return if any
    if result ~= nil then
        return output_handler(result)
    end
    -- -- If native_server:call_tool is a synchronous call but the handler didn't return anything or is running asynchronously given the res:send() arch
    -- -- Wait for the handler to finish until TIMEOUT as if the user didn't call res:send() this will never finish
    -- -- The only place the nativeserver is called synchronously is while a chat resolving #resource variable in the chat when submitted
    local start_time = os.time()
    if not opts.callback then
        while not tool_finished do
            vim.wait(500)
            if os.time() - start_time > TIMEOUT then
                return output_handler(nil, "Tool execution timed out")
            end
        end
        return tool_result, tool_error
    end
end

function NativeServer:access_resource(uri, opts)
    opts = opts or {}
    -- Create output handler
    -- Track if resource has called to prevent double-handling
    local resource_accessed = false
    local resource_result, resource_error
    local function output_handler(result, err)
        if resource_accessed then
            return
        end
        resource_result = result
        resource_error = err
        resource_accessed = true
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
    -- Find matching resource/template and extract params
    local resource, params = self:find_matching_resource(uri)
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

    local editor_info = buf_utils.get_editor_info()
    -- Create req/res objects with full context
    local req = Request.ResourceRequest:new({
        server = self,
        resource = resource,
        uri = uri,
        template = resource.uriTemplate,
        editor_info = editor_info,
        params = params,
        caller = opts.caller,
    })
    local res = Response.ResourceResponse:new(output_handler, uri, resource.uriTemplate)

    -- Call resource handler with req/res
    local ok, result = pcall(resource.handler, req, res)
    if not ok then
        log.warn(string.format("Resource access failed: %s", result))
        return res:error(result --[[@as string]])
    end

    -- Handle synchronous return if any
    if result ~= nil then
        return output_handler(result)
    end
    -- call_resource will be called synchronously when chat is trying to resolve #resourcevariable(that we populated dynamically based on available servers) when chat:submit(),
    -- If native_server:call_resource is a synchronous call but the handler didn't return anything or is running asynchronously given the res:send() arch
    -- Wait for the handler to finish until TIMEOUT as if the user didn't call res:send() this will never finish
    local start_time = os.time()
    if not opts.callback then
        while not resource_accessed do
            vim.wait(500)
            if (os.time() - start_time) > TIMEOUT then
                return output_handler(nil, "Resource access timed out")
            end
        end
        return resource_result, resource_error
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
    disable = disable or false
    -- if disable then
    self.status = "disabled"
    -- else
    --     self.status = "disconnected"
    -- end
end

return NativeServer
