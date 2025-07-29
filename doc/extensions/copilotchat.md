# CopilotChat Integration

Add MCP capabilities to [CopilotChat.nvim](https://github.com/CopilotC-Nvim/CopilotChat.nvim) by adding it as an extension. CopilotChat now has native function-calling support, making it easy to integrate MCP tools and resources.

## Features

- **Tool Integration**: Register MCP tools as CopilotChat functions with proper schemas
- **Resource Integration**: Register MCP resources as CopilotChat functions for easy access
- **Server Groups**: Functions are organized by MCP server name for better organization
- **Real-time Updates**: Automatic updates in CopilotChat when MCP servers change

## Setup

#### Enable CopilotChat Extension

Add CopilotChat as an extension in your MCPHub configuration:

```lua
require("mcphub").setup({
    extensions = {
        copilotchat = {
            enabled = true,
            convert_tools_to_functions = true,     -- Convert MCP tools to CopilotChat functions
            convert_resources_to_functions = true, -- Convert MCP resources to CopilotChat functions  
            add_mcp_prefix = false,                -- Add "mcp_" prefix to function names
        }
    }
})
```

#### Configuration Options

- **`convert_tools_to_functions`**: When `true`, all MCP tools are registered as CopilotChat functions
- **`convert_resources_to_functions`**: When `true`, all MCP resources are registered as CopilotChat functions
- **`add_mcp_prefix`**: When `true`, adds "mcp_" prefix to all function names (e.g., `mcp_github__get_issue`)

## Usage

### MCP Tools 

When `convert_tools_to_functions = true`, all MCP tools become available as CopilotChat functions. Functions are automatically organized by server name, making it easy to see all tools from a specific MCP server. Tool names follow the pattern `server_name__tool_name`:

**Examples:**
- `@neovim__read_file` - Read a file using the neovim server
- `@github__create_issue` - Create a GitHub issue  
- `@fetch__fetch` - Fetch web content

![Tool Functions](https://github.com/user-attachments/assets/7c16bc7e-a9df-4afc-9736-2ee6a39919a9)

### MCP Resources 

You can use `#` to access MCP resources as variables in CopilotChat. In addition, when `convert_resources_to_functions = true`, all MCP resources will also be available as CopilotChat functions:

**Examples:**
- `#neovim__Buffer` - Access current buffer content
- `@neovim__Buffer` - Get current buffer content (as a function)

![Resource Functions](https://github.com/user-attachments/assets/7f77bf1e-12b7-4745-a87b-40181a619733)



## Example Workflow

1. **Start CopilotChat** and type `@` to see available functions
2. **Select MCP functions** from your connected servers
3. **Use tools**: `@github__create_issue Fix the navigation bug`
4. **Access resources**: `@neovim__current_buffer Show me the current file content`
5. **Organize by server**: Browse functions grouped by MCP server

![Server Groups](https://github.com/user-attachments/assets/adc556bb-7d5f-4d22-820a-a7daeb0ac72c)
