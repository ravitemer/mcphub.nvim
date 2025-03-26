# Native MCP Server Development Guide

This guide explains how to create native Lua servers for mcphub.nvim using the MCP (Model Communication Protocol) architecture.

## Server Lifecycle

1. **Server Definition** - First, create a server definition:
```lua
---@type ServerDef
local server_def = {
    -- Required fields
    name = "example",
    capabilities = {
        tools = { ... },
        resources = { ... },
        resourceTemplates = { ... }
    },
    -- Optional fields
    displayName = "Example Server",
}
```

2. **Server Registration** - The definition is used to create a NativeServer instance:
```lua
---@class NativeServer
---@field name string Server name
---@field displayName string Display name
---@field status "connected"|"disconnected"|"disabled" Server status
---@field capabilities MCPCapabilities Server capabilities
```

## Two Ways to Register Servers

1. **Configuration-based Approach** - Register via setup config:
```lua
require("mcphub").setup({
    native_servers = {
        weather = {
            name = "weather",
            displayName = "Weather Server",
            capabilities = {
                tools = {
                    {
                        name = "get_weather",
                        description = "Get current weather for a city",
                        inputSchema = {
                            type = "object",
                            properties = {
                                city = {
                                    type = "string",
                                    description = "City name",
                                },
                            },
                        },
                        handler = function(req, res)
                            return res:text("Weather in " .. req.params.city .. ": ☀️ 22°C"):send()
                        end,
                    },
                },
                resources = {
                    {
                        name = "london_weather",
                        uri = "weather://current/london",
                        description = "Current London weather",
                        handler = function(req, res)
                            return res:text("London: ☀️ 22°C"):send()
                        end,
                    },
                },
                resourceTemplates = {
                    {
                        name = "city_weather",
                        uriTemplate = "weather://current/{city}",
                        description = "Get weather for any city",
                        handler = function(req, res)
                            return res:text(req.params.city .. ": ⛅ 20°C"):send()
                        end,
                    },
                },
            },
        },
    },
})
```

2. **API-based Approach** - Register and build incrementally:
```lua
local mcphub = require("mcphub")

-- Start by adding a tool. It iwll create the server if it is not already present.
mcphub.add_tool("weather", {
    name = "get_weather",
    description = "Get current weather for a city",
    inputSchema = {
        type = "object",
        properties = {
            city = {
                type = "string",
                description = "City name",
                examples = ["London", "New York"],
            },
        },
    },
    handler = function(req, res)
        -- Simulate weather API call
        local weather_data = {
            London = { temp = 22, condition = "☀️" },
            ["New York"] = { temp = 25, condition = "⛅" },
        }
        local city_data = weather_data[req.params.city]
        
        if city_data then
            res:text(string.format(
                "Weather in %s: %s %d°C",
                req.params.city,
                city_data.condition,
                city_data.temp
            )):send()
        else
            res:error("City not found")
        end
    end,
})

-- Add a static resource for London weather
mcphub.add_resource("weather", {
    name = "london_weather",
    uri = "weather://current/london",
    description = "Current London weather",
    handler = function(req, res)
        res:text("London: ☀️ 22°C"):send()
    end,
})

-- Add a template for any city
mcphub.add_resource_template("weather", {
    name = "city_weather",
    uriTemplate = "weather://current/{city}",
    description = "Get weather for any city",
    handler = function(req, res)
        if req.params.city == "London" then
            return res:text("London: ☀️ 22°C"):send()
        else
            return res:text(req.params.city .. ": ⛅ 20°C"):send()
        end
    end,
})
```

## Component Types

### Tools
```lua
---@class MCPTool
---@field name string Tool name (required)
---@field handler fun(req: ToolRequest, res: ToolResponse): table|nil Tool implementation (required)
---@field description? string Tool description
---@field inputSchema? MCPJsonSchema JSON Schema for arguments

-- Example minimal tool:
local tool = {
    name = "greet",
    handler = function(req, res)
        return res:text("Hello"):send()
    end
}
```

### Resources
```lua
---@class MCPResource
---@field uri string Static resource URI (required)
---@field handler fun(req: ResourceRequest, res: ResourceResponse): table|nil Resource implementation (required)
---@field name? string Resource name
---@field description? string Resource description
---@field mimeType? string Resource MIME type

-- Example minimal resource:
local resource = {
    uri = "example://greeting",
    handler = function(req, res)
        return res:text("Hello"):send()
    end
}
```

### Resource Templates
```lua
---@class MCPResourceTemplate
---@field uriTemplate string URI template with {params} (required)
---@field handler fun(req: ResourceRequest, res: ResourceResponse): table|nil Template implementation (required)
---@field name? string Template name
---@field description? string Template description
---@field mimeType? string Default MIME type

-- Example minimal template:
local template = {
    uriTemplate = "users://{id}",
    handler = function(req, res)
        return res:text("User " .. req.params.id):send()
    end
}
```

### JSON Schema Types
```lua
---@class MCPJsonSchema
---@field type "object" Schema type (always object for MCP)
---@field properties table<string,MCPSchemaProperty> Property definitions
---@field required? string[] List of required property names

---@class MCPSchemaProperty
---@field type "string"|"number"|"boolean"|"array"|"object" Property type
---@field description string Property description
---@field items? MCPSchemaProperty Schema for array items
---@field properties? table<string,MCPSchemaProperty> Properties for nested objects
---@field default? any Default value
---@field enum? any[] List of allowed values
---@field minimum? number Minimum value for numbers
---@field maximum? number Maximum value for numbers
---@field pattern? string Regex pattern for strings
---@field format? string String format (e.g. "date-time")
---@field minLength? number Minimum string length
---@field maxLength? number Maximum string length
---@field minItems? number Minimum array length
---@field maxItems? number Maximum array length
```

## Request Objects

### Tool Requests
```lua
---@class ToolRequest
---@field params table Tool arguments
---@field context { tool: MCPTool } Context with tool definition
---@field server NativeServer Reference to server instance
```

### Resource Requests
```lua
---@class ResourceRequest
---@field params table Template parameters
---@field uri string Full resource URI
---@field uriTemplate string|nil Original template if from template
---@field context { resource: MCPResource } Context with resource definition
---@field server NativeServer Reference to server instance
```

## Response Objects 

### Response Content Types

```lua
---@alias MCPResourceContent { uri: string, text?: string, blob?: string, mimeType: string }
---@alias MCPContent { type: "text"|"image"|"resource", text?: string, data?: string, resource?: MCPResourceContent, mimeType?: string }
```

### Tool Responses
```lua
---@class ToolResponse
---@field text fun(self: ToolResponse, text: string): ToolResponse Add text content
---@field image fun(self: ToolResponse, data: string, mime: string): ToolResponse Add image content
---@field resource fun(self: ToolResponse, resource: MCPResourceContent): ToolResponse Add resource content
---@field error fun(self: ToolResponse, message: string, details?: table): table Send error response
---@field send fun(self: ToolResponse, result?: table): table Send response

-- Examples:
res:text("Hello world")
res:image(image_data, "image/png")
res:resource({
    uri = "example://file.txt",
    text = "File content",
    mimeType = "text/plain"
})
res:error("Something went wrong")
res:send() -- Always end with send()
```

### Resource Responses
```lua
---@class ResourceResponse 
---@field text fun(self: ResourceResponse, text: string, mime?: string): ResourceResponse Add text content
---@field blob fun(self: ResourceResponse, data: string, mime?: string): ResourceResponse Add binary content
---@field image fun(self: ResourceResponse, data: string, mime: string): ResourceResponse Add image content
---@field error fun(self: ResourceResponse, message: string, details?: table): table Send error response
---@field send fun(self: ResourceResponse, result?: table): table Send response

-- Examples:
res:text("Content", "text/plain") -- mime defaults to text/plain
res:blob(binary_data) -- mime defaults to application/octet-stream
res:image(image_data, "image/png") -- Helper for image blobs
res:error("Resource not found")
res:send() -- Always end with send()
```

## Error Handling
```lua
-- Basic error
return res:error("Invalid input")

-- Error with details
return res:error("Failed to process", {
    code = 500,
    details = "More information..."
})
```

## Async Operations
```lua
-- Async tool handler
function handler(req, res)
    vim.schedule(function()
        res:text("Async result"):send()
    end)
    -- Don't return for async handlers
end
```

## Best Practices

1. **Type Safety**
   - Use provided type annotations
   - Define input schemas for tools
   - Follow URI naming conventions

2. **Error Handling**
   - Use res:error() for proper error responses
   - Include meaningful error messages
   - Add details for debugging

3. **Code Organization**
   - Keep handlers focused and pure
   - Use descriptive names
   - Document capabilities

4. **Testing**
   - Test both sync and async operations
   - Validate inputs early
   - Use log.debug() for debugging

## Development Tips

1. Start with minimal implementations using required fields
2. Add optional fields as needed for better UX
3. Use types for better IDE support and error catching
4. Document your server's capabilities clearly
5. Follow the example server patterns
