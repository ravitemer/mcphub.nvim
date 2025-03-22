# Native MCP Server Development Guide

This guide explains how to create native Lua servers for mcphub.nvim using the MCP (Model Communication Protocol) architecture.

## Quick Start

```lua
-- my_server.lua
return {
    name = "my_server",
    displayName = "My Server",
    capabilities = {
        tools = {
            {
                name = "greet",
                description = "Greet someone",
                handler = function(req, res)
                    local name = req.params.name or "world"
                    return res:text("Hello, " .. name):send()
                end
            }
        },
        resources = {
            {
                uri = "greeting://default",
                handler = function(req, res)
                    return res:text("Hello from resource"):send()
                end
            }
        }
    }
}
```

## Server Definition

A native server is defined by a table with:
- `name`: Unique identifier
- `displayName`: Human-readable name
- `capabilities`: Table of tools and resources

### Tools

Tools are functions that can be called with arguments:

```lua
tools = {
    {
        name = "my_tool",           -- Required: Tool name
        description = "...",        -- Optional: Tool description
        inputSchema = {            -- Optional: JSON Schema for arguments
            type = "object",
            properties = {
                name = {
                    type = "string",
                    description = "Name to greet"
                }
            }
        },
        handler = function(req, res)
            -- Tool implementation
            return res:text("Hello"):send()
        end
    }
}
```

### Resources

Resources are URI-addressable content:

```lua
resources = {
    {
        uri = "myscheme://fixed/path",  -- Fixed URI
        description = "...",            -- Optional description
        mimeType = "text/plain",        -- Default MIME type
        handler = function(req, res)
            return res:text("Content"):send()
        end
    }
}

resourceTemplates = {
    {
        uriTemplate = "users://{username}/profile",  -- URI template
        description = "User profile",
        handler = function(req, res)
            -- Access params from template
            local username = req.params.username
            return res:text("Profile for " .. username):send()
        end
    }
}
```

## Request Object

The request object provides access to:

### For Tools:
```lua
req = {
    params = {},      -- Tool arguments
    server = {},      -- Reference to server instance
    context = {
        tool = {}     -- Tool definition
    }
}
```

### For Resources:
```lua
req = {
    params = {},      -- URI template parameters
    uri = "",        -- Full URI
    uriTemplate = "", -- Original template
    server = {},      -- Reference to server instance
    context = {
        resource = {} -- Resource definition
    }
}
```

## Response Object

The response object provides methods to build responses:

### For Tools:
```lua
-- Add text content
res:text("Hello world")

-- Add image content
res:image(image_data, "image/png")

-- Send error
res:error("Something went wrong")

-- Chain methods
res:text("Hello"):text("World"):send()
```

### For Resources:
```lua
-- Send text content (uri stored internally)
res:text("Content", "text/plain")  -- mime type optional

-- Send binary content
res:blob(data, "application/octet-stream")

-- Send error
res:error("Resource not found")
```

All responses must end with `:send()` to return the result.

## Error Handling

Errors can be returned using `res:error()`:

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

For async operations, don't return immediately:

```lua
function handler(req, res)
    vim.schedule(function()
        -- Async work
        res:text("Async result"):send()
    end)
    -- Don't return anything for async handlers
end
```

## Example Implementations

See the builtin servers in `lua/mcphub/native/builtin/` for complete examples:
- `listing.lua`: Shows tool and resource implementations
- File/buffer handling
- URI template usage
- Error handling
- Async operations

## Best Practices

1. Use `req.params` for all input parameters
2. Always end responses with `:send()`
3. Use proper error handling with `res:error()`
4. Use URI templates with descriptive param names
5. Include proper documentation and input schemas
6. Keep handlers focused and composable
7. Properly handle async operations

## Development Tips

1. Use `log.debug()` for debugging
2. Test both sync and async handlers
3. Validate inputs early
4. Follow URI naming conventions
5. Use meaningful error messages
6. Keep resource handlers pure
7. Document your server's capabilities
