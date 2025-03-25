---@class ToolRequest
---@field params table Tool arguments
---@field tool MCPTool Tool definition
---@field caller table Caller context
---@field hub MCPHub Hub class
---@field editor_info EditorInfo Editor information
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
---@field params table Template parameters
---@field uri string Full resource URI
---@field uriTemplate string|nil Original template if from template
---@field resource MCPResource Resource definition
---@field caller table Additional context
---@field editor_info EditorInfo Editor information
---@field hub MCPHub Hub class
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
