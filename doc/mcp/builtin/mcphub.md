# MCPHub Server

The MCPHub server (`mcphub`) provides management utilities for the MCPHub plugin itself. It allows LLMs to dynamically control MCP server lifecycle, query system state, and access comprehensive documentation.

## Tools

### `get_current_servers`
Retrieve the current state of all MCP servers, including both connected and disabled servers.

**Parameters:**
- `include_disabled` (boolean, optional): Whether to include disabled servers (default: true)
- `format` (string, optional): Response format - "detailed" or "summary" (default: "detailed")

**Response Formats:**

**Summary Format:**
```
# Current MCP Server Status

Connected servers (3): github, filesystem, search
Disabled servers (2): database, analytics
```

**Detailed Format:**
Provides complete server information including:
- Server capabilities (tools, resources, prompts)
- Connection status and uptime
- Configuration details
- Available tools with descriptions

### `toggle_mcp_server` 
Start or stop MCP servers dynamically based on task requirements.

**Parameters:**
- `server_name` (string, required): Name of the MCP server to control
- `action` (string, required): Action to perform - "start" or "stop"

## Resources

#### `MCPHub Plugin Docs` (`mcphub://docs`)
Comprehensive documentation for the mcphub.nvim plugin.

#### `MCPHub Native Server Guide` (`mcphub://native_server_guide`)
Complete guide for creating Lua Native MCP servers.

**Intended For:**
- LLMs helping users create custom servers
- Developer documentation and reference
- Advanced plugin customization

#### `MCPHub Changelog` (`mcphub://changelog`)
Version history and feature updates for the plugin.


## Prompts

#### `create_native_server`
Assists users in creating custom native MCP servers with guided prompts.

**Parameters:**
- `mcphub_setup_file` (string, required): Path to file where `mcphub.setup({})` is called (default: Neovim config directory)

**Functionality:**
- Loads comprehensive native server creation guide
- Provides context about user's Neovim configuration
- Integrates with chat plugins for seamless assistance
