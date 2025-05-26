---
prev: false
next:
    text: 'Installation'
link: '/installation'
---

# What is MCP HUB?

MCPHub.nvim is a MCP client for neovim that seamlessly integrates [MCP (Model Context Protocol)](https://modelcontextprotocol.io/) servers into your editing workflow. It provides an intuitive interface for managing, testing, and using MCP servers with your favorite chat plugins.

![Image](https://github.com/user-attachments/assets/21fe7703-9bc3-4c01-93ce-3230521bd5bf)

> [!IMPORTANT]
> It is recommended to read this page before going through the rest of the documentation.

## How does MCP Hub work?

Let's break down how MCP Hub operates in simple terms:

### MCP Config File

Like any MCP client, MCP Hub requires a configuration file to define the MCP servers you want to use. This file is typically located at `~/.config/mcphub/servers.json`. MCP Hub supports local `stdio` servers as well as remote `streamable-http` or `sse` servers. This is similar to `claude_desktop_config.json` file for Claude desktop or `mcp.json` file used by VSCode. In fact you can use the same file for MCP Hub as well with some additional benefits. It looks something like:
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
    "remote-server": {
      "url": "https://api.example.com/mcp"
    }
  }
}
```

### Servers Manager

- When MCP Hub's `setup()` is called typically when Neovim starts, it launches the nodejs binary, [mcp-hub](https://github.com/ravitemer/mcp-hub) with the `servers.json` file.
- The `mcp-hub` binary reads `servers.json` file and starts the MCP servers.
- It provides a express REST API endpoint (default: `http://localhost:37373`) for clients to interact with MCP servers
- The plugin communicates with this endpoint to:
  - Start/stop MCP servers
  - Execute tools, resources, prompts etc
  - Handle real-time server events when tools or resources are changed.

### Usage

- Use `:MCPHub` command to open the interface
- Adding (`<A>`), editing (`<e>`), deleting (`<d>`) MCP servers in easy and intuitive with MCP Hub. You don't need to edit the `servers.json` file directly. 
- Install servers from the Marketplace (`M`)
- Toggle servers, tools, and resources etc
- Test tools and resources directly in Neovim

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
| | [CopilotChat.nvim](https://github.com/CopilotC-Nvim/CopilotChat.nvim) | ✅ | In-built support [Draft](https://github.com/CopilotC-Nvim/CopilotChat.nvim/pull/1029) | 
| **Marketplace** ||||
| | Server Discovery | ✅ | Browse from verified MCP servers |
| | Installation | ✅ | Manual and auto install with AI |
| **Advanced** ||||
| | Smart File-watching | ✅ | Smart updates with config file watching |
| | Multi-instance | ✅ | All neovim instances stay in sync |
| | Shutdown-delay | ✅ | Can run as systemd service with configure delay before stopping the hub |
| | Lua Native MCP Servers | ✅ | Write once , use everywhere. Can write tools, resources, prompts directly in lua |
| | Dev Mode | ✅ | Hot reload MCP servers on file changes for development |

## Next Steps

- [Installation Guide](/installation) - Set up MCPHub in your Neovim
- [Configuration Guide](/configuration) - Learn about configuring MCP Hub



