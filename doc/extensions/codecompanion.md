# CodeCompanion Integration

<p>
<video muted controls src="https://github.com/user-attachments/assets/70181790-e949-4df6-a690-c5d7a212e7d1"></video>
</p>

Add MCP capabilities to [CodeCompanion.nvim](https://github.com/olimorris/codecompanion.nvim) by adding it as an extension. 

## Features

- **Flexible Tool Access**: Multiple ways to use MCP tools - from broad `@mcp` access to granular individual tools
- **Server Groups**: Access all tools from a specific server (e.g., `@neovim`, `@github`, `@tree_sitter`)
- **Individual Tools**: Use specific tools with clear namespacing (e.g., `@neovim__read_file`, `@github__create_issue`)
- **Custom Tool Groups**: Create your own tool combinations for specific workflows
- **Resource Variables**: Utilize MCP resources as context variables using the `#` prefix (e.g., `#resource_name`)
- **Slash Commands**: Execute MCP prompts directly using `/mcp:prompt_name` slash commands
- **Rich Media Support**: Supports 🖼 images and other media types as shown in the demo
- **Real-time Updates**: Automatic updates in CodeCompanion when MCP servers change

## MCP Hub Extension

Register MCP Hub as an extension in your CodeCompanion configuration:

```lua
require("codecompanion").setup({
  extensions = {
    mcphub = {
      callback = "mcphub.extensions.codecompanion",
      opts = {
        make_tools = true,              -- Enable individual tools (@server__tool) and server groups (@server)
        show_server_tools_in_chat = true, -- Show individual tools in chat completion (when make_tools=true)
        show_result_in_chat = true,      -- Show tool results directly in chat buffer
        make_vars = true,                -- Convert MCP resources to #variables for prompts
        make_slash_commands = true,      -- Add MCP prompts as /slash commands
      }
    }
  }
})
```

## Usage

MCP Hub provides multiple ways to access MCP tools in CodeCompanion, giving you flexibility from broad access to fine-grained control:

### Tool Access

#### 1. Universal MCP Access (`@mcp`)
Adds all available MCP servers to the system prompt and provides LLM with `use_mcp_tool` and `access_mcp_resource` tools.
```
@mcp What files are in the current directory?
```

#### 2. Server Groups (when `make_tools = true`)
Access all tools from a specific server. The available groups depend on your connected MCP servers:
```
@neovim Read the main.lua file    # If you have neovim server
@github Create an issue           # If you have github server  
@fetch Get this webpage           # If you have fetch server
```

Server groups are automatically created based on your connected MCP servers. Check your MCP Hub UI to see which servers you have connected.

#### 3. Individual Tools (when `make_tools = true`)
Pinpoint specific functionality with namespaced tools. Tool names depend on your connected servers:
```
@neovim__read_file Show me the config file
@fetch__fetch Get this webpage content
@github__create_issue File a bug report
```

Use the MCP Hub UI or CodeCompanion's tool completion to discover available tools.

#### 4. Custom Tool Sets
Create your own tool combinations by mixing MCP tools with existing CodeCompanion tools:

Example configuration for custom tool groups:

```lua
require("codecompanion").setup({
  strategies = {
    chat = {
      tools = {
        groups = {
          ["github_pr_workflow"] = {
            description = "GitHub operations from issue to PR",
            tools = {
              -- File operations
              "neovim__read_files", "neovim__write_file", "neovim__replace_in_file",
              -- GitHub operations
              "github__create_issue", "github__create_pull_request", "github__get_file_contents",
              "github__create_or_update_file", "github__list_issues", "github__search_code"
            },
          },
        },
      },
    },
  },
  extensions = {
    mcphub = {
      callback = "mcphub.extensions.codecompanion",
      opts = {
        make_tools = true,  -- Required for individual tools
        -- ... other options
      }
    }
  }
})
```


Then use your custom groups:
```
@github_pr_workflow Fix this bug, create tests, and submit a PR with proper documentation
```

**Important Notes:**
- Tool names depend on your connected MCP servers
- Use MCP Hub UI or Codecompanion's tool completion to see available servers and tools  
- Tool names follow the pattern `servername__toolname`
- Mix MCP tools with CodeCompanion's built-in tools (`cmd_runner`, `editor`, `files`, etc.)
- Each MCP tool can be individually auto-approved for fine-grained control (see Auto-Approval section)

### Resources as Variables
If `make_vars = true`, MCP resources become available as variables prefixed with `#`:

```
Fix diagnostics in the file #neovim://diagnostics/current  
Analyze the current buffer #neovim:buffer
```

*Example: Accessing LSP diagnostics*:

![image](https://github.com/user-attachments/assets/fb04393c-a9da-4704-884b-2810ff69f59a)

### Slash Commands
If `make_slash_commands = true`, MCP prompts are available as slash commands:

```
/mcp:code_review
/mcp:explain_function
/mcp:generate_tests
```

*Example: Using an MCP prompt via slash command*:

![image](https://github.com/user-attachments/assets/678a06a5-ada9-4bb5-8f49-6e58549c8f32)



## Auto-Approval

By default, whenever codecompanion calls `use_mcp_tool` or `access_mcp_resource` tool or a specific tool on some MCP server, it shows a confirm dialog with tool name, server name and arguments.

![Image](https://github.com/user-attachments/assets/201a5804-99b6-4284-9351-348899e62467)

#### Global Auto-Approval

You can set `auto_approve` to `true` to automatically approve all MCP tool calls without user confirmation:

```lua
require("mcphub").setup({
    -- This sets vim.g.mcphub_auto_approve to true by default (can also be toggled from the HUB UI with `ga`)
    auto_approve = true, 
})
```

This also sets `vim.g.mcphub_auto_approve` variable to `true`. You can also toggle this option in the MCP Hub UI with `ga` keymap. You can see the current auto approval status in the Hub UI.

![Image](https://github.com/user-attachments/assets/64708065-3428-4eb3-82a5-e32d2d1f98c6)

#### Fine-Grained Auto-Approval

![Image](https://github.com/user-attachments/assets/131bfed2-c4e7-4e2e-ba90-c86e6ca257fd)

![Image](https://github.com/user-attachments/assets/befd1d44-bca3-41f6-a99a-3d15c6c8a5f5)

For more control, configure auto-approval per server or per tool in your `servers.json`:

```json
{
    "mcpServers": {
        "trusted-server": {
            "command": "npx",
            "args": ["trusted-mcp-server"],
            "autoApprove": true  // Auto-approve all tools on this server
        },
        "partially-trusted": {
            "command": "npx", 
            "args": ["some-mcp-server"],
            "autoApprove": ["read_file", "list_files"]  // Only auto-approve specific tools
        }
    }
}
```

You can also toggle auto-approval from the Hub UI:
- Press `a` on a server line to toggle auto-approval for all tools on that server
- Press `a` on an individual tool to toggle auto-approval for just that tool
- Resources are always auto-approved (no configuration needed)

#### Auto-Approval Priority

The system checks auto-approval in this order:
1. **Global**: `vim.g.mcphub_auto_approve = true` (approves everything)
2. **CodeCompanion**: `vim.g.codecompanion_auto_tool_mode = true` (toggled via `gta` in chat buffer)
3. **Server-specific**: `autoApprove` field in server config
4. **Default**: Show confirmation dialog
