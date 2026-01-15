# Workspaces

MCP Hub supports project-local configuration files that enable isolated MCP server setups per project. This solves the key problem of needing different server configurations for different projects.

<p>
<video muted controls src="https://github.com/user-attachments/assets/dd83f591-ffb2-43ad-8ef6-16de34c54997"></video>
</p>

## Why Workspaces?

Consider these common scenarios:

**Filesystem Access**: `mcp-server-filesystem` needs access to specific project directories:

```json
{
  "mcpServers": {
    "filesystem": {
      "command": "uvx",
      "args": ["mcp-server-filesystem", "${CWD}"]
    }
  }
}
```

**Language Server Integration**: `mcp-language-server` requires project-specific workspace and LSP configurations:

```json
{
  "mcpServers": {
    "lsp": {
      "command": "mcp-language-server",
      "args": ["--workspace", "${CWD}", "--lsp", "typescript-language-server", "--", "--stdio"]
    }
  }
}
```

Without workspaces, you'd need to manually edit the global config for every project. With workspaces, each project gets its own configuration automatically.

## How It Works

#### 1. Project Detection

When you open Neovim in a directory, MCP Hub searches upward from the current directory for:

- `.mcphub/servers.json` (MCP Hub specific)
- `.vscode/mcp.json` (VS Code compatibility)
- `.cursor/mcp.json` (Cursor compatibility)

The first file found defines the project boundary.

#### 2. Hub Instance Creation

Each detected workspace gets:

- **Unique port**: Generated from project path hash (e.g., `40380`)
- **Isolated processes**: Separate `mcp-hub` instance with its own servers
- **Merged configuration**: Project config overrides global config
- **Project context**: Hub starts with `cwd` set to project directory

#### 3. Automatic Switching

When you change directories (`cd`), MCP Hub automatically:

- Detects the new workspace
- Connects to the appropriate hub instance
- Switches to the correct server configuration

## Configuration

Enable workspaces in your MCP Hub setup:

```lua
require("mcphub").setup({
    workspace = {
        enabled = true, -- Default: true
        look_for = { ".mcphub/servers.json", ".vscode/mcp.json", ".cursor/mcp.json" },
        reload_on_dir_changed = true, -- Auto-switch on directory change
        port_range = { min = 40000, max = 41000 }, -- Port range for workspace hubs
        get_port = nil, -- Optional function for custom port assignment
    },
})
```

You can additionally set workspace to be always enabled regardless of having config files. This would create a unique hub for every project directory.

```lua
require("mcphub").setup({
    workspace = {
        enabled = "always",
    },
})
```

## Example Setup

#### Global Config (`~/.config/mcphub/servers.json`)

```json
{
  "mcpServers": {
    "memory": {
      "command": "uvx",
      "args": ["@modelcontextprotocol/server-memory"]
    }
  }
}
```

#### Project Config (`.mcphub/servers.json`)

```json
{
  "mcpServers": {
    "filesystem": {
      "command": "uvx",
      "args": ["mcp-server-filesystem", "${CWD}"]
    },
    "lsp": {
      "command": "mcp-language-server",
      "args": ["--workspace", "${CWD}", "--lsp", "lua-language-server", "--", "--stdio"]
    }
  }
}
```

#### Environment Variables

`CWD` will be set to the working directory of the current running `mcp-hub`. Basic environment variables (`HOME`, `USER`, `TERM`, `SHELL`, etc.) are always available.

Additional variables can be set via:

1. **global_env** configuration in MCP Hub setup
2. **Process environment** when the hub starts

```lua
require("mcphub").setup({
    global_env = function(context)
        return {
            DBUS_SESSION_BUS_ADDRESS = os.getenv("DBUS_SESSION_BUS_ADDRESS") or "",
        }
    end,
})
```

⚠️ **Note**: Environment variables are captured when the hub starts. To refresh environment, restart the hub with `R` in the MCP Hub UI.

#### Custom Port Assignment

By default, MCP Hub generates ports by hashing the project path. You can override this with a custom function:

```lua
require("mcphub").setup({
    workspace = {
        get_port = function()
            local project_name = vim.fn.fnamemodify(vim.fn.getcwd(), ":t")

            -- Use fixed ports for specific projects
            if project_name == "critical-project" then
                return 45000
            elseif project_name == "test-project" then
                return 46000
            end

            -- Return nil to use default hash-based port generation
            return nil
        end,
    },
})
```

This is useful when you need consistent, predictable port numbers for specific projects.

## UI Overview

The MCP Hub interface shows clear workspace organization:

![Image](https://github.com/user-attachments/assets/c3b0894e-df6d-4882-a204-4b763d6f1646)

#### Active Hubs

![Image](https://github.com/user-attachments/assets/af6949c6-b4bb-423f-b7df-6123cb0eb54c)

#### Config View

The Config view (`C`) shows all configuration files with tabs for easy switching between global and project configs.

![Image](https://github.com/user-attachments/assets/934dd162-bcf0-400e-8f96-45cf3b68d41f)

## Workspace Actions

- **`<l>`**: Expand/collapse workspace details
- **`<d>`**: Kill workspace process (with confirmation)
- **`<gc>`**: Change directory to workspace
- **`<h>`**: Collapse expanded workspace

## Troubleshooting

#### Hub Not Switching

- Ensure `reload_on_dir_changed = true`
- Check that config file exists in project root
- Use `:cd` instead of shell directory changes

#### Port Conflicts

- Check "Active Hubs" section for conflicts
- Kill stale processes with `<d>`
- Restart with `R`

#### Environment Variables Not Updated

- Environment is captured when hub starts
- Restart hub with `R` to get latest environment
- Use `global_env` for dynamic values
