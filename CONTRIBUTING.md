# Contributing to mcphub.nvim

Thank you for considering contributing to mcphub.nvim! This document provides guidelines and information to help you get started contributing to the project.

## Project Overview

mcphub.nvim acts as a frontend to the [mcp-hub](https://github.com/ravitemer/mcp-hub) backend, which provides core functionality like watching the `servers.json` file, starting/stopping servers and hosting an express server for client connections.

The express server provides several key endpoints:
- `/api/health` - Server health and status checks
- `/api/events` - SSE endpoint for real-time events (logs, server updates, etc.)
- `/api/servers/*` - Endpoints for tools, resources, prompts

## Development Environment Setup

### Prerequisites

- Neovim 0.8.0+
- Node.js 18.0+
- [lua-language-server](https://github.com/LuaLS/lua-language-server)
- [stylua](https://github.com/JohnnyMorganz/StyLua)
- [plenary.nvim](https://github.com/nvim-lua/plenary.nvim)
- [tmux](https://github.com/tmux/tmux) (recommended for development)

### Setting up mcp-hub for Development

1. Clone the mcp-hub repository:
```bash
git clone https://github.com/ravitemer/mcp-hub.git
cd mcp-hub
```

2. Configure mcphub.nvim to use local mcp-hub:
```lua
local mcphub = require("mcphub")

-- First clear the log file
local file = io.open(vim.fn.expand("~/mcphub.log"), "w")
if file then
    file:write("")
    file:close()
end

mcphub.setup({
    -- Use local mcp-hub during development
    cmd = "node",
    cmdArgs = {
        "/path/to/mcp-hub/src/utils/cli.js",  -- Point to local mcp-hub
    },
    shutdown_delay = 0,  -- During development, stop immediately when neovim exits
    
    -- Enhanced logging for development
    log = {
        to_file = true,
        file_path = vim.fn.expand("~/mcphub.log"),
        level = vim.log.levels.DEBUG,
    },
})
```

### Development Workflow with tmux

For effective development, use a tmux-based setup with multiple panes:

![Image](https://github.com/user-attachments/assets/598f8194-0924-4bea-93b3-c708da26fa59)

1. Main editor pane with mcphub.nvim code
2. Second pane showing real-time mcp-hub logs:
```bash 
tail -f ~/.mcp-hub/logs/mcp-hub.log
```
3. Third pane watching mcphub.nvim plugin logs:
```bash
tail -f ~/mcphub.log
```

This setup allows you to:
- Monitor both frontend (plugin) and backend (mcp-hub) logs in real-time
- See how changes affect the communication between components
- Debug issues more effectively by correlating events

## Project Structure

- `lua/mcphub/` - Main plugin code
  - `init.lua` - Plugin entry point and setup
  - `state.lua` - Global state management
  - `hub.lua` - Core MCP Hub functionality 
  - `extensions/` - Chat plugin integrations
  - `native/` - Native MCP server implementations
  - `ui/` - User interface components
  - `utils/` - Shared utility functions

## Making Changes

### 1. Fork & clone 
- mcphub.nvim (plugin)
- Fork [mcp-hub](https://github.com/ravitemer/mcp-hub)  (backend) - If your changes need to update the mcp-hub

### 2. Set up development environment:
- See the above [Development Environment Setup](#development-environment-setup) for details

### 3. Make changes:
- Follow existing code patterns
- Update relevant documentation
- Follow existing patterns for:
  - Error handling
  - Logging 
- Add tests for new functionality
- Run `make format` to format code using stylua
- Run `make docs` to generate documentation

#### Code Style
- Use [stylua](https://github.com/JohnnyMorganz/StyLua) for code formatting
- Configuration is in `stylua.toml`
- Run `make format` before submitting PRs
- Follow existing code patterns and naming conventions

#### Documentation
Documentation is built using [panvimdoc](https://github.com/kdheepak/panvimdoc):

```bash
make docs  # Generate plugin documentation
```

### 4. Testing:

- mcphub.nvim uses [Mini.Test](https://github.com/echasnovski/mini.nvim/tree/main/lua/mini/test) for testing:

```bash
make test           # Run all tests
make test_file FILE=path/to/test_file.lua  # Run specific test file
```
- Ensure mcphub.nvim tests pass
- When adding new features, please include tests in the appropriate test file under `tests/`.
- Verify logs show expected behavior
- Test with different chat plugins if relevant


## Pull Request Process

1. Update documentation if behavior changes
2. Add tests for new features
3. Format code: `make format`
4. Generate docs: `make docs`
5. Include:
   - Clear description
   - Related issue references
   - Screenshots/gifs if UI changes
   - Log examples if relevant

## Getting Help

- Join our [Discord server](https://discord.gg/NTqfxXsNuN)
- Check detailed [Wiki](https://github.com/ravitemer/mcphub.nvim/wiki)
- Read announcements in Discussions for feature details

## License

By contributing to mcphub.nvim, you agree that your contributions will be licensed under the MIT License.
