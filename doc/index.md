---
prev: false
next:
    text: 'Installation'
link: '/installation'
---

# What is MCP HUB?

MCPHub.nvim is a MCP client for neovim that seamlessly integrates [MCP (Model Context Protocol)](https://modelcontextprotocol.io/) servers into your editing workflow. It provides an intuitive interface for managing, testing, and using MCP servers with your favorite chat plugins.

![Image](https://github.com/user-attachments/assets/7c299fbd-4820-4065-8b07-50db66179d3d)

> [!IMPORTANT]
> It is recommended to read this page before going through the rest of the documentation.

## How does MCP Hub work?

Let's break down how MCP Hub operates in simple terms:

### MCP Config File

Like any MCP client, MCP Hub requires a configuration file to define the MCP servers you want to use. This file is typically located at `~/.config/mcphub/servers.json`. MCP Hub supports local `stdio` servers as well as remote `streamable-http` or `sse` servers. 

**VS Code Compatibility**: MCP Hub supports VS Code's `.vscode/mcp.json` format directly, including the `servers` key, `${env:}` syntax, and predefined variables. You can use the same file for MCP Hub, VS Code, Claude Desktop, Cursor, Cline, Zed, etc. It looks something like:
```js
// Example: ~/.config/mcphub/servers.json
{
  "mcpServers": {
    "fetch": {
      "command": "uvx",
      "args": [
        "mcp-server-fetch"
      ]
    },
    "github": {
      "url": "https://api.githubcopilot.com/mcp/",
      "headers": {
        "Authorization": "Bearer ${GITHUB_PERSONAL_ACCESS_TOKEN}"
      }
    }
  }
}
```

### Servers Manager

- When MCP Hub's `setup()` is called typically when Neovim starts, it launches the nodejs binary, [mcp-hub](https://github.com/ravitemer/mcp-hub) with the `servers.json` file.
- The `mcp-hub` binary reads `servers.json` file and starts the MCP servers.
- It provides two key interfaces:
  1. **Management API** (default: `http://localhost:37373/api`):
     - Used by this plugin to manage MCP servers
     - Start/stop servers, execute tools, access resources
     - Handle real-time server events
  2. **Unified MCP Endpoint** (`http://localhost:37373/mcp`):
     - A single MCP server that other MCP clients can connect to
     - Exposes ALL capabilities from ALL managed servers
     - Automatically namespaces capabilities to prevent conflicts
     - Use this endpoint in Claude Desktop, Cline, or any MCP client

For example, instead of configuring each MCP client with multiple servers:
```json
{
    "mcpServers" : {
        "filesystem": { ... },
        "search": { ... },
        "database": { ... }
    }
}
```

Just configure them to use MCP Hub's unified endpoint:
```json
{
    "mcpServers" : {
        "Hub": {
            "url" : "http://localhost:37373/mcp"  
        }
    }
}
```

### Usage

- Use `:MCPHub` command to open the interface
- Adding (`<A>`), editing (`<e>`), deleting (`<d>`) MCP servers in easy and intuitive with MCP Hub. You don't need to edit the `servers.json` file directly. 
- Install servers from the Marketplace (`M`)
- Toggle servers, tools, and resources etc
- Test tools and resources directly in Neovim

### Builtin Native Servers

MCPHub includes two native servers that run directly within Neovim:

- **Neovim Server**: Comprehensive file operations, terminal access, LSP integration, and buffer management
- **MCPHub Server**: Plugin management utilities, server lifecycle control, and documentation access

These servers provide essential functionality without external dependencies and offer deep Neovim integration.

### Workspace-Aware Configuration

MCP Hub automatically detects project-local configuration files (`.mcphub/servers.json`, `.vscode/mcp.json`, `.cursor/mcp.json`) and creates isolated hub instances for each workspace. This enables:

- **Project-specific servers**: `mcp-server-filesystem` with project paths, `mcp-language-server` with project-specific LSP configurations
- **Isolated environments**: Each project gets its own hub instance and server processes  
- **Configuration merging**: Project configs override global settings while preserving global servers

Users can view all active workspace hubs and switch between them seamlessly through the UI.

### Chat Integrations

- MCP Hub provides integrations with popular chat plugins like [Avante](https://github.com/yetone/avante.nvim), [CodeCompanion](https://github.com/olimorris/codecompanion.nvim), [CopilotChat](https://github.com/CopilotC-Nvim/CopilotChat.nvim).
- LLMs can use MCP servers through our `@mcp` tool.
- Resources show up as `#variables` in chat.
- Prompts become `/slash_commands`.

## Feature Support Matrix

| Category | Feature | Support | Details |
|----------|---------|---------|-------|
| [**Capabilities**](https://modelcontextprotocol.io/specification/2025-03-26/server) ||||
| | Tools | ✅ | Full support |
| | 🔔 Tool List Changed | ✅ | Real-time updates |
| | Resources | ✅ | Full support |
| | 🔔 Resource List Changed | ✅ | Real-time updates |
| | Resource Templates | ✅ | URI templates |
| | Prompts | ✅ | Full support |
| | 🔔 Prompts List Changed | ✅ | Real-time updates |
| | Roots | ❌ | Not supported |
| | Sampling | ❌ | Not supported |
| **MCP Server Transports** ||||
| | [Streamable-HTTP](https://modelcontextprotocol.io/specification/2025-03-26/basic/transports#streamable-http) | ✅ | Primary transport protocol for remote servers |
| | [SSE](https://modelcontextprotocol.io/specification/2025-03-26/basic/transports#backwards-compatibility) | ✅ | Fallback transport for remote servers |
| | [STDIO](https://modelcontextprotocol.io/specification/2025-03-26/basic/transports#stdio) | ✅ | For local servers |
| **Authentication for remote servers** ||||
| | [OAuth](https://modelcontextprotocol.io/specification/2025-03-26/basic/authorization) | ✅ | With PKCE flow |
| | Headers | ✅ | For API keys/tokens |
| **Chat Integration** ||||
| | [Avante.nvim](https://github.com/yetone/avante.nvim) | ✅ | Tools, resources, resourceTemplates, prompts(as slash_commands) |
| | [CodeCompanion.nvim](https://github.com/olimorris/codecompanion.nvim) | ✅ | Tools, resources, templates, prompts (as slash_commands), 🖼 image responses | 
| | [CopilotChat.nvim](https://github.com/CopilotC-Nvim/CopilotChat.nvim) | ✅ | Tools, resources, function calling support |
| **Marketplace** ||||
| | Server Discovery | ✅ | Browse from verified MCP servers |
| | Installation | ✅ | Manual and auto install with AI |
| **Configuration** ||||
| | Universal `${}` Syntax | ✅ | Environment variables and command execution across all fields |
| | VS Code Compatibility | ✅ | Support for `servers` key, `${env:}`, `${input:}`, predefined variables |
| | JSON5 Support | ✅ | Comments and trailing commas via [`lua-json5`](https://github.com/Joakker/lua-json5) |
| **Workspace Management** ||||
| | Project-Local Configs | ✅ | Automatic detection and merging with global config |
| **Advanced** ||||
| | Smart File-watching | ✅ | Smart updates with config file watching |
| | Multi-instance | ✅ | All neovim instances stay in sync |
| | Shutdown-delay | ✅ | Can run as systemd service with configure delay before stopping the hub |
| | Lua Native MCP Servers | ✅ | Write once , use everywhere. Can write tools, resources, prompts directly in lua |
| | Dev Mode | ✅ | Hot reload MCP servers on file changes for development |

## Next Steps

- [Installation Guide](/installation) - Set up MCPHub in your Neovim
- [Configuration Guide](/configuration) - Learn about configuring MCP Hub
