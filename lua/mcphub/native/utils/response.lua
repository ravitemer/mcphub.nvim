---@class BaseResponse
local BaseResponse = {}
BaseResponse.__index = BaseResponse

function BaseResponse:new(output_handler)
    local instance = {
        output_handler = output_handler,
        result = {},
    }
    return setmetatable(instance, self)
end

function BaseResponse:send(result)
    local final_result = result or self.result
    if self.output_handler then
        -- Async with callback
        self.output_handler({
            result = final_result,
        })
    else
        -- Sync return
        return {
            result = final_result,
        }
    end
end

---@class ToolResponse : BaseResponse
local ToolResponse = setmetatable({}, { __index = BaseResponse })
ToolResponse.__index = ToolResponse

function ToolResponse:new(output_handler)
    local instance = BaseResponse:new(output_handler)
    instance.result = { content = {} }
    setmetatable(instance, self)
    return instance
end

function ToolResponse:text(text)
    if type(text) ~= "string" then
        text = vim.inspect(text)
    end
    table.insert(self.result.content, {
        type = "text",
        text = text,
    })
    return self
end

function ToolResponse:image(data, mime)
    table.insert(self.result.content, {
        type = "image",
        data = data,
        mimeType = mime,
    })
    return self
end

function ToolResponse:error(message, details)
    if type(message) ~= "string" then
        message = vim.inspect(message)
    end
    local result = {
        isError = true,
        content = {
            {
                type = "text",
                text = message,
            },
        },
    }

    -- Add details if provided
    if details then
        table.insert(result.content, {
            type = "text",
            text = "Details: " .. vim.inspect(details),
        })
    end

    -- Auto-send error response
    return self:send(result)
end

---@class ResourceResponse : BaseResponse
local ResourceResponse = setmetatable({}, { __index = BaseResponse })
ResourceResponse.__index = ResourceResponse

function ResourceResponse:new(output_handler, uri, template)
    local instance = BaseResponse:new(output_handler)
    instance.uri = uri
    instance.template = template
    instance.result = { contents = {} }
    setmetatable(instance, self)
    return instance
end

function ResourceResponse:text(text, mime)
    if type(text) ~= "string" then
        text = vim.inspect(text)
    end
    table.insert(self.result.contents, {
        uri = self.uri,
        text = text,
        mimeType = mime or "text/plain",
    })
    return self
end

function ResourceResponse:blob(data, mime)
    table.insert(self.result.contents, {
        uri = self.uri,
        blob = data,
        mimeType = mime or "application/octet-stream",
    })
    return self
end

function ResourceResponse:error(message, details)
    if type(message) ~= "string" then
        message = vim.inspect(message)
    end
    -- For resources, we return error as a text resource
    self.result = {
        contents = {
            {
                uri = self.uri,
                text = message .. (details and ("\nDetails: " .. vim.inspect(details)) or ""),
                mimeType = "text/plain",
            },
        },
    }
    return self:send(self.result)
end

return {
    ToolResponse = ToolResponse,
    ResourceResponse = ResourceResponse,
}
