# API Reference

MCPHub.nvim provides a Lua API that you can use to interact with MCP servers programmatically. This reference documents the core functions and objects available.

## Core API

#### Hub Instance

```lua
---Get the current MCPHub instance
---@return MCPHub.Hub | nil
local hub = require("mcphub").get_hub_instance()
```

Returns the current `MCPHub.Hub` instance, which provides methods for interacting with MCP servers.

#### State Instance

```lua
---Get the current state of the MCPHub
---@return MCPHub.State
local state = require("mcphub").get_state()
```

#### Event System

```lua
-- Subscribe to events
require("mcphub").on(event_name, callback)

-- Unsubscribe from events
require("mcphub").off(event_name, callback)

-- Subscribe to multiple events at once
require("mcphub").on({"servers_updated", "tool_list_changed"}, callback)
```

Available events:
- `servers_updated`: Triggered when the list of servers or their status changes
- `tool_list_changed`: Triggered when a server's tools are updated
- `resource_list_changed`: Triggered when a server's resources are updated
- `prompt_list_changed`: Triggered when a server's prompts are updated

## Native MCP Server API

MCPHub allows you to create Lua-based MCP servers directly in Neovim:

```lua
---Check if a server exists
---@param name string
require("mcphub").is_native_server(name)

---Add a new server
---@param name string
---@param server_def NativeServerDef
require("mcphub").add_server(name, server_def)

---Add a tool to a server (creates server if it doesn't exist)
---@param server_name string
---@param tool_def MCPTool
require("mcphub").add_tool(server_name, tool_def)

---Add a resource to a server
---@param server_name string
---@param resource_def MCPResource
require("mcphub").add_resource(server_name, resource_def)

---Add a resource template to a server
---@param server_name string
---@param template_def MCPResourceTemplate
require("mcphub").add_resource_template(server_name, template_def)

---Add a prompt to a server
---@param server_name string
---@param prompt_def MCPPrompt
require("mcphub").add_prompt(server_name,prompt_def)
```

See [Native Server Guide](/mcp/native/index) for detailed usage examples.

## Hub Instance Methods

When you have a hub instance, you can use these methods to interact with MCP servers:

### Server Management

```lua
-- Get all active MCP servers
---@param include_disabled? boolean
---@return MCPServer[]
local servers = hub:get_servers()

-- Get all server tools
---@return EnhancedMCPTool[]
local tools = hub:get_tools()

-- Get all server resources
---@return EnhancedMCPResource[]
local resources = hub:get_resources()

-- Get all server resource templates
---@return EnhancedMCPResourceTemplate[]
local resource_templates = hub:get_resource_templates()

-- Get all server prompts
---@return EnhancedMCPPrompt[]
local prompts = hub:get_prompts()

-- Start a specific MCP server
---@param name string Server name to start
---@param opts? { via_curl_request?:boolean,callback?: function }
hub:start_mcp_server(server_name, options)

-- Stop a specific MCP server
---@param name string Server name to stop
---@param disable boolean Whether to disable the server
---@param opts? { via_curl_request?: boolean, callback?: function } Optional callback(response: table|nil, error?: string)
hub:stop_mcp_server(server_name, disable, options)

-- Refresh the server list
hub:refresh()

-- Hard refresh (force update from servers)
hub:hard_refresh()

-- Restart the hub
hub:restart()
```

### Tool and Resource Invocation

```lua
-- Call a tool (synchronously)
local response, err = hub:call_tool(server_name, tool_name, args, {
    parse_response = true  -- Parse response to LLM-suitable text
})

-- Call a tool (asynchronously)
hub:call_tool(server_name, tool_name, args, {
    parse_response = true,
    callback = function(response, err)
        -- Handle response
    end
})

-- Access resource (synchronously)
local response, err = hub:access_resource(server_name, resource_uri, {
    parse_response = true
})

-- Access resource (asynchronously)
hub:access_resource(server_name, resource_uri, {
    parse_response = true,
    callback = function(response, err)
        -- Handle response
    end
})

-- Execute a prompt
local response, err = hub:get_prompt(server_name, prompt_name, args, {
    parse_response = true
})
```

### Prompt Helpers

```lua
-- Get system prompts for chat plugins
local prompts = hub:generate_prompts()
-- prompts.active_servers: Lists active servers
-- prompts.use_mcp_tool: Instructions for tool usage with example
-- prompts.access_mcp_resource: Instructions for resource access with example

-- Get active servers as prompt text
local active_servers_text = hub:get_active_servers_prompt()

-- Convert a server to text representation
local server_text = hub:convert_server_to_text(server)
```


## Usage Examples

#### Basic Tool Call

```lua
local hub = require("mcphub").get_hub_instance()
local response, err = hub:call_tool("neovim", "read_file", {
    path = "/path/to/file.txt"
})

if err then
    print("Error calling tool: " .. err)
else
    print("File content:", response.result.content[1].text)
end
```

#### Asynchronous Resource Access

```lua
hub:access_resource("lsp", "lsp://diagnostics/current_file", {
    callback = function(response, err)
        if err then
            vim.notify("Error accessing resource: " .. err, vim.log.levels.ERROR)
            return
        end
        
        local diagnostics_text = response.result.contents[1].text
        vim.notify("Current file diagnostics:\n" .. diagnostics_text)
    end
})
```

#### Creating a Native MCP Server

```lua
require("mcphub").add_server("math", {
    name = "math",
    description = "Mathematical operations server",
    capabilities = {
        tools = {
            {
                name = "calculate",
                description = "Perform a calculation",
                inputSchema = {
                    type = "object",
                    properties = {
                        expression = {
                            type = "string",
                            description = "Mathematical expression to evaluate"
                        }
                    },
                    required = {"expression"}
                },
                handler = function(req, res)
                    local expr = req.params.expression
                    local success, result = pcall(loadstring, "return " .. expr)
                    if success then
                        res:text("Result: " .. tostring(result())):send()
                    else
                        res:text("Error evaluating expression: " .. expr):send()
                    end
                end
            }
        }
    }
})
```

See [Native Server Guide](/mcp/native/index) for more examples.
