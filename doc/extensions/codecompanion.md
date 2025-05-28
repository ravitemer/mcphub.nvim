# CodeCompanion Integration

<p>
<video muted controls src="https://github.com/user-attachments/assets/70181790-e949-4df6-a690-c5d7a212e7d1"></video>
</p>

Add MCP capabilities to [CodeCompanion.nvim](https://github.com/olimorris/codecompanion.nvim) by adding it as an extension. 

## Features

- Access MCP tools via the `@mcp` tool in the chat buffer.
- Utilize MCP resources as context variables using the `#` prefix (e.g., `#resource_name`).
- Execute MCP prompts directly using `/mcp:prompt_name` slash commands.
- Supports 🖼 images as shown in the demo.
- Receive real-time updates in CodeCompanion when MCP servers change.

## MCP Hub Extension

Register MCP Hub as an extension in your CodeCompanion configuration:

```lua
require("codecompanion").setup({
  extensions = {
    mcphub = {
      callback = "mcphub.extensions.codecompanion",
      opts = {
        show_result_in_chat = true,  -- Show mcp tool results in chat
        make_vars = true,            -- Convert resources to #variables
        make_slash_commands = true,  -- Add prompts as /slash commands
      }
    }
  }
})
```

## Usage

Once configured, you can interact with MCP Hub within the CodeCompanion chat buffer:

-   **Tool Access:** Type `@mcp` to add available MCP servers to the system prompt, enabling the LLM to use registered MCP tools.
-   **Resources as Variables:** If `make_vars = true`, MCP resources become available as variables prefixed with `#`. You can include these in your prompts (e.g., `Summarize the issues in #mcp:lsp:get_diagnostics`):

*Example: Accessing LSP diagnostics*:

![image](https://github.com/user-attachments/assets/fb04393c-a9da-4704-884b-2810ff69f59a)

**Prompts as Slash Commands:** If `make_slash_commands = true`, MCP prompts are available as slash commands (e.g., `/mcp:prompt_name`). Arguments are handled via `vim.ui.input`.

*Example: Using an MCP prompt via slash command*:

![image](https://github.com/user-attachments/assets/678a06a5-ada9-4bb5-8f49-6e58549c8f32)




## Auto-Approval

By default, whenever codecompanion calls `use_mcp_tool` or `access_mcp_resource` tool, it shows a confirm dialog with tool name, server name and arguments.

![Image](https://github.com/user-attachments/assets/201a5804-99b6-4284-9351-348899e62467)

### Global Auto-Approval

You can set `auto_approve` to `true` to automatically approve all MCP tool calls without user confirmation:

```lua
require("mcphub").setup({
    -- This sets vim.g.mcphub_auto_approve to true by default (can also be toggled from the HUB UI with `ga`)
    auto_approve = true, 
})
```

This also sets `vim.g.mcphub_auto_approve` variable to `true`. You can also toggle this option in the MCP Hub UI with `ga` keymap. You can see the current auto approval status in the Hub UI.

![Image](https://github.com/user-attachments/assets/64708065-3428-4eb3-82a5-e32d2d1f98c6)

### Fine-Grained Auto-Approval

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

### Auto-Approval Priority

The system checks auto-approval in this order:
1. **Global**: `vim.g.mcphub_auto_approve = true` (approves everything)
2. **CodeCompanion**: `vim.g.codecompanion_auto_tool_mode = true` (toggled via `gta` in chat buffer)
3. **Server-specific**: `autoApprove` field in server config
4. **Default**: Show confirmation dialog


