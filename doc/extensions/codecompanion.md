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
        format_action = function(action_name, tool)
            -- Replace 'use_mcp_tool' with actual tool name and params.
            if action_name == 'use_mcp_tool' then
                local name = string.format(
                    '%s/%s',
                    tool.args.server_name,
                    tool.args.tool_name
                )
                local tool_input = vim.deepcopy(tool.args.tool_input)
                -- Cut too large params.
                if name == 'filesystem/edit_file' then
                  tool_input.edits = '󰩫'
                elseif name == 'filesystem/write_file' then
                  tool_input.content = '󰩫'
                end
                local args = vim.inspect(tool_input):gsub('%s+', ' ')
                return name .. ' ' .. args
            end
        end,
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

### Function-Based Auto-Approval

For maximum control, provide a function that decides approval based on the specific tool call:

```lua
require("mcphub").setup({
    auto_approve = function(params)
        -- Respect CodeCompanion's auto tool mode when enabled
        if vim.g.codecompanion_auto_tool_mode == true then
            return true -- Auto approve when CodeCompanion auto-tool mode is on
        end
        
        -- Auto-approve GitHub issue reading
        if params.server_name == "github" and params.tool_name == "get_issue" then
            return true -- Auto approve
        end
        
        -- Block access to private repos
        if params.arguments.repo == "private" then
            return "You can't access my private repo" -- Error message
        end
        
        -- Auto-approve safe file operations in current project
        if params.tool_name == "read_file" then
            local path = params.arguments.path or ""
            if path:match("^" .. vim.fn.getcwd()) then
                return true -- Auto approve
            end
        end
        
        -- Check if tool is configured for auto-approval in servers.json
        if params.is_auto_approved_in_server then
            return true -- Respect servers.json configuration
        end
        
        return false -- Show confirmation prompt
    end,
})
```

**Parameters available in the function:**
- `params.server_name` - Name of the MCP server
- `params.tool_name` - Name of the tool being called (nil for resources)
- `params.arguments` - Table of arguments passed to the tool
- `params.action` - Either "use_mcp_tool" or "access_mcp_resource"
- `params.uri` - Resource URI (for resource access)
- `params.is_auto_approved_in_server` - Boolean indicating if tool is configured for auto-approval in servers.json

**Return values:**
- `true` - Auto-approve the call
- `false` - Show confirmation prompt
- `string` - Deny with error message
- `nil` - Show confirmation prompt (same as false)

### Auto-Approval Priority

The system checks auto-approval in this order:
1. **Function**: Custom `auto_approve` function (if provided)
2. **Server-specific**: `autoApprove` field in server config
3. **Default**: Show confirmation dialog




