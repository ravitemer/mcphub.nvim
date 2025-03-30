---@class ToolRequest
---@field params table Tool arguments (validated against inputSchema)
---@field tool MCPTool Complete tool definition including dynamic fields
---@field server NativeServer Server instance
---@field caller table Additional context from caller
---@field editor_info EditorInfo Current editor state
local ToolRequest = {}
ToolRequest.__index = ToolRequest

function ToolRequest:new(opts)
    local instance = {
        server = opts.server,
        params = opts.arguments, -- Tool arguments become params
        tool = opts.tool, -- Store tool definition
        caller = opts.caller or {},
        editor_info = opts.editor_info,
    }
    return setmetatable(instance, self)
end

---@class ResourceRequest
---@field params table<string, string> Template parameters from URI
---@field uri string Complete requested URI
---@field uriTemplate string|nil Original template pattern if from template
---@field resource MCPResource|MCPResourceTemplate Complete resource definition including dynamic fields
---@field server NativeServer Server instance
---@field caller table Additional context from caller
---@field editor_info EditorInfo Current editor state
local ResourceRequest = {}
ResourceRequest.__index = ResourceRequest

function ResourceRequest:new(opts)
    local instance = {
        server = opts.server,
        params = opts.params, -- Template params
        resource = opts.resource, -- Store resource definition
        caller = opts.caller or {},
        uri = opts.uri,
        uriTemplate = opts.template,
        editor_info = opts.editor_info,
    }
    return setmetatable(instance, self)
end

return {
    ToolRequest = ToolRequest,
    ResourceRequest = ResourceRequest,
}
