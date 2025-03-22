---@class BaseRequest
local BaseRequest = {}
BaseRequest.__index = BaseRequest

function BaseRequest:new(opts)
    local instance = {
        server = opts.server, -- Reference to server instance
        params = opts.params or {}, -- All parameters
        context = opts.context or {}, -- For any additional context
    }
    return setmetatable(instance, self)
end

---@class ToolRequest : BaseRequest
local ToolRequest = setmetatable({}, { __index = BaseRequest })
ToolRequest.__index = ToolRequest

function ToolRequest:new(opts)
    local instance = BaseRequest:new({
        server = opts.server,
        params = opts.arguments, -- Tool arguments become params
        context = {
            tool = opts.tool, -- Store tool definition
        },
    })
    return setmetatable(instance, self)
end

---@class ResourceRequest : BaseRequest
local ResourceRequest = setmetatable({}, { __index = BaseRequest })
ResourceRequest.__index = ResourceRequest

function ResourceRequest:new(opts)
    local instance = BaseRequest:new({
        server = opts.server,
        params = opts.params, -- Template params
        context = {
            resource = opts.resource, -- Store resource definition
        },
    })
    instance.uri = opts.uri
    instance.uriTemplate = opts.template
    return setmetatable(instance, self)
end

return {
    ToolRequest = ToolRequest,
    ResourceRequest = ResourceRequest,
}
