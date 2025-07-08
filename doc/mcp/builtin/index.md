# Builtin Native Servers

MCPHub.nvim includes two native MCP servers that run directly within Neovim, providing essential functionality without external dependencies.

## Available Servers

### 1. Neovim Server (`neovim`)

The primary server providing comprehensive file operations, terminal access, LSP integration, and buffer management.

**Key Features:**
- File system operations (read, write, edit, search)
- Terminal command execution and Lua code execution
- LSP diagnostics and buffer inspection
- Interactive file editing with diff preview
- Environment and workspace information

[View Neovim Server Documentation](./neovim)

### 2. MCPHub Server (`mcphub`)

Management utilities for the MCPHub plugin itself, allowing LLMs to control MCP server lifecycle and access documentation.

**Key Features:**
- Start/stop MCP servers dynamically
- Query server status and capabilities
- Access plugin documentation and guides
- Native server creation assistance

[View MCPHub Server Documentation](./mcphub)

