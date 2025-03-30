# Lua Native MCP Server Development for MCPHub.nvim

## Understanding MCP Servers

The Model Context Protocol (MCP) is a standardized way for tools and resources to be exposed to Large Language Models (LLMs). An MCP server:

1. Provides a standardized interface for:
   - Tools: Functions that LLMs can call
   - Resources: Data that LLMs can access
   - Resource Templates: Dynamic, parameterized resources

2. Example MCP servers:
   - GitHub (for repository operations)
   - Figma (for design access)
   - Database servers (for data queries)
   - Custom API servers (wrapping existing services)

The protocol ensures consistent interaction patterns regardless of the underlying implementation.

## What are Native MCP Servers?

Native MCP Servers in MCPHub.nvim implement the MCP protocol directly in Neovim using Lua, eliminating the need for separate processes. They:

1. Run within Neovim's runtime
2. Have direct access to Neovim's APIs
3. Can be dynamically added/modified
4. Work with any chat plugin through MCPHub

While many chat plugins have their own tool systems, this leads to limitations:
- Tools need reimplementing for each plugin
- Each plugin has different APIs
- No standard way to handle resources
- Limited response types
- Plugin-specific state management
- Breaking changes with updates

Native MCP Servers solve these problems by implementing the Model Context Protocol directly in Neovim:

1. **Complete MCP Implementation**
   - Full support for MCP tools and resources
   - Standard request/response formats
   - URI-based resource system
   - Compatible with any MCP client

2. **Write Once, Run Anywhere**
   - Single implementation works with all chat plugins
   - No plugin-specific code needed
   - Tools and resources share common interface
   - Future-proof against plugin changes

3. **Rich Response System**
   - Standard response types (text, images, blobs)
   - Chainable response methods
   - Built-in error handling
   - MIME type support

4. **Deep Neovim Integration**
   - Direct access to Neovim APIs
   - Native Lua performance
   - Buffer/window management
   - Editor state awareness

5. **Centralized Management**
   - MCPHub handles server lifecycle
   - Consistent state management
   - Runtime capability updates
   - Cross-plugin coordination

Your tools and resources work exactly like regular MCP servers, but with the added benefits of:
- Running directly in Neovim
- Native Lua performance
- Direct editor access
- No external dependencies

## Creating Native Servers

You can create native servers in two ways:

### 1. Configuration-based Setup
Define complete server in your Neovim config:
```lua
require('mcphub').config({
  native_servers = {
    weather = {
      name = "weather",
      capabilities = {
        tools = {
          {
            name = "get_weather",
            description = "Get weather for a city",
            inputSchema = {
              type = "object",
              properties = {
                city = {
                  type = "string",
                  description = "City name"
                }
              }
            },
            handler = function(req, res)
              return res:text("Weather in " .. req.params.city .. ": Sunny"):send()
            end
          }
        },
        resources = {
          {
            name = "current",
            uri = "weather://london",
            description = "Current London weather",
            handler = function(req, res)
              return res:text("London: Sunny, 22°C"):send()
            end
          }
        }
      }
    }
  }
})
```

### 2. Incremental Creation
Add capabilities one by one as needed:
```lua
-- Add a tool - creates server if it doesn't exist
mcphub.add_tool("weather", {
  name = "get_weather",
  description = "Get weather for a city",
  inputSchema = {
    type = "object",
    properties = {
      city = { type = "string", description = "City name" }
    }
  },
  handler = function(req, res)
    return res:text("Weather in " .. req.params.city .. ": Sunny"):send()
  end
})

-- Add a resource to same server
mcphub.add_resource("weather", {
  name = "london",
  uri = "weather://london",
  description = "Current London weather",
  handler = function(req, res)
    return res:text("London: Sunny, 22°C"):send()
  end
})

-- Add a template for any city
mcphub.add_resource_template("weather", {
  name = "city",
  uriTemplate = "weather://{city}",
  description = "Get weather for any city",
  handler = function(req, res)
    return res:text(req.params.city .. ": Sunny, 20°C"):send()
  end
})
```

Both methods allow you to:
- Create new servers with custom functionality
- Extend existing servers (like adding tools to 'neovim' server)
- Keep your code organized and maintainable

## Type Definitions

Native servers use these core types:

### Server Types
```lua
---@class ServerSchema
---@field name string # Unique server identifier
---@field displayName? string # Human-friendly name
---@field capabilities MCPCapabilities # Server capabilities

---@class MCPCapabilities
---@field tools MCPTool[] # List of tools
---@field resources MCPResource[] # List of resources
---@field resourceTemplates MCPResourceTemplate[] # List of templates
```

### Tool Types
```lua
---@class MCPTool
---@field name string # Tool identifier
---@field description string|fun():string # Description (can be dynamic)
---@field inputSchema? table|fun():table # JSON Schema (can be dynamic)
---@field handler fun(req: ToolRequest, res: ToolResponse) # Handler function

---@class ToolRequest
---@field params any # Validated input parameters
---@field tool MCPTool # Tool definition
---@field server NativeServer # Server instance
---@field caller table # Additional context
---@field editor_info EditorInfo # Editor state

---@class ToolResponse
---@field text fun(content: string): ToolResponse # Add text
---@field image fun(data: string, mime: string): ToolResponse # Add image
---@field resource fun(resource: MCPResourceContent): ToolResponse # Add resource
---@field error fun(message: string, details?: table): nil # Send error
---@field send fun(): table # Send response
```

### Resource Types
```lua
---@class MCPResource
---@field name string # Resource identifier
---@field description string|fun():string # Description (can be dynamic)
---@field uri string # Static URI
---@field handler fun(req: ResourceRequest, res: ResourceResponse) # Handler function

---@class MCPResourceTemplate
---@field name string # Template identifier
---@field description string|fun():string # Description (can be dynamic)
---@field uriTemplate string # URI pattern with parameters
---@field handler fun(req: ResourceRequest, res: ResourceResponse) # Handler function

---@class ResourceRequest
---@field params table<string, string> # URI parameters
---@field uri string # Requested URI
---@field uriTemplate? string # Original template
---@field resource MCPResource|MCPResourceTemplate # Resource definition
---@field server NativeServer # Server instance
---@field caller table # Additional context
---@field editor_info EditorInfo # Editor state

---@class ResourceResponse
---@field text fun(content: string, mime?: string): ResourceResponse # Add text
---@field blob fun(data: string, mime?: string): ResourceResponse # Add binary
---@field image fun(data: string, mime: string): ResourceResponse # Add image
---@field error fun(message: string, details?: table): nil # Send error
---@field send fun(): table # Send response
```


Note:
- Description fields can be strings or functions
- Dynamic descriptions are evaluated when:
- Showing in UI
- Generating prompts
- Creating documentation
- Similarly, inputSchema can be dynamic


##### Caller Information

When your tool or resource handler is called from a chat plugin, it receives important context:

```lua
---@class CallerInfo
---@field type "avante"|"codecompanion"|"hubui" # Which system called the tool
---@field avante? table # Avante-specific context (when type is "avante")
---@field codecompanion? table # CodeCompanion-specific context (when type is "codecompanion")
---@field hubui? table # Hub UI context (when type is "hubui")
---@field meta table # Additional metadata
```
Each caller type provides different context:

```lua
mcphub.add_tool("workspace", {
    name = "analyze_buffer",
    description = "Analyze current buffer",
    handler = function(req, res)
    -- Get correct buffer based on caller
    local bufnr
    if req.caller.type == "codecompanion" then
    -- Get buffer from CodeCompanion chat context
    local chat = req.caller.codecompanion.chat
    bufnr = chat.context.bufnr
    local is_var = req.caller.meta.is_within_variable -- true if called from #variable

    elseif req.caller.type == "avante" then
    -- Get buffer from Avante code context
    bufnr = req.caller.avante.code.bufnr

    elseif req.caller.type == "hubui" then
    -- Using hub UI context
    bufnr = req.caller.hubui.context.bufnr or 0
    end

    -- Use the buffer number
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    return res:text(#lines .. " lines found"):send()
    end
})
```

##### Editor Information

The `req.editor_info` field provides the current editor state:

```lua
---@class EditorInfo
---@field last_active BufferInfo # Currently active buffer
---@field buffers BufferInfo[] # List of all buffers

---@class BufferInfo
---@field name string # Buffer name
---@field filename string # Full file path
---@field windows number[] # Window IDs showing this buffer
---@field winnr number # Primary window number
---@field cursor_pos number[] # Cursor position [row, col]
---@field filetype string # Buffer filetype
---@field line_count number # Total lines
---@field is_visible boolean # Whether buffer is visible
---@field is_modified boolean # Whether buffer is modified
---@field is_loaded boolean # Whether buffer is loaded
---@field lastused number # Last used timestamp
---@field bufnr number # Buffer number
```

```lua
mcphub.add_tool("buffer", {
    name = "get_info",
    description = "Get buffer information",
    handler = function(req, res)
    local info = req.editor_info
    local active = info.last_active

    -- Access current buffer state
    local details = {
    name = active.filename,
    type = active.filetype,
    lines = active.line_count,
    cursor = active.cursor_pos,
    modified = active.is_modified,
    visible = active.is_visible
    }

    -- List all open buffers
    local buffers = {}
    for _, buf in ipairs(info.buffers) do
    table.insert(buffers, buf.filename)
      end

      return res:text(vim.inspect({
            active = details,
            open_buffers = buffers
            })):send()
                end
})
```

This context system allows your tools to:
- Access the correct buffer when called from different plugins
  - Adapt behavior based on the caller
- Handle plugin-specific features (like CodeCompanion variables)
  - Get current editor state consistently

### Response Objects

Both tool and resource handlers use chainable response methods that accumulate content until `send()` is called:

### Text Responses
```lua
-- Basic text response
res:text("Hello world"):send()
-- Produces: { content = {{ type = "text", text = "Hello world" }}}

-- Multiple text parts
res:text("Part 1")
   :text("Part 2")
   :send()
-- Produces:
-- { content = {
--     { type = "text", text = "Part 1" },
--     { type = "text", text = "Part 2" }
--   }}

-- With MIME type
res:text(json_string, "application/json"):send()
-- Produces: { content = {{ type = "text", text = json_string, mimeType = "application/json" }}}
```

### Image and Binary
```lua
-- Image response
res:image(png_data, "image/png"):send()
-- Produces: { content = {{ type = "image", data = png_data, mimeType = "image/png" }}}

-- Resource-only binary
res:blob(pdf_data, "application/pdf"):send()
-- Produces: { content = {{ type = "blob", data = pdf_data, mimeType = "application/pdf" }}}
```

### Mixed Content
```lua
-- Combine different types
res:text("Image description:")
   :image(img_data, "image/png")
   :text("Additional info")
   :send()
-- Produces:
-- { content = {
--     { type = "text", text = "Image description:" },
--     { type = "image", data = img_data, mimeType = "image/png" },
--     { type = "text", text = "Additional info" }
--   }}
```

### Error Responses
```lua
-- Simple error
res:error("Operation failed")
-- Produces: { isError = true, content = {{ type = "text", text = "Operation failed" }}}

-- Error with details
res:error("Invalid input", {
  path = req.params.path,
  reason = "File not found"
})
-- Produces:
-- {
--   isError = true,
--   content = {
--     { type = "text", text = "Invalid input" },
--     { type = "text", text = "Details: { path = '...', reason = 'File not found' }" }
--   }
-- }
```

Note:
- `:send()` is required to resolve the response
- Errors auto-send and don't need `:send()`
- Each content piece is tracked internally until sent
- Type and MIME info helps LLMs understand content


## Server Implementation Examples

Here are practical examples showing different ways to create servers:

### 1. Git Integration
```lua
-- Add tools incrementally
mcphub.add_tool("git", {
  name = "get_status",
  description = "Get git status of current repository",
  handler = function(req, res)
    local status = vim.fn.system("git status --porcelain")
    if vim.v.shell_error ~= 0 then
      return res:error("Not a git repository")
    end
    return res:text(status):send()
  end
})

mcphub.add_resource("git", {
  name = "branch_info",
  uri = "git://branch",
  description = "Get current branch information",
  handler = function(req, res)
    local branch = vim.fn.system("git branch --show-current")
    return res:text(branch):send()
  end
})

mcphub.add_resource_template("git", {
  name = "commit_info",
  uriTemplate = "git://commits/{count}",
  description = "Get recent commits",
  handler = function(req, res)
    local count = tonumber(req.params.count) or 5
    local commits = vim.fn.system(
      string.format("git log -n %d --oneline", count)
    )
    return res:text(commits):send()
  end
})
```
