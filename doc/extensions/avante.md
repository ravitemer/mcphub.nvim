# Avante Integration

<p>
<video muted src="https://github.com/user-attachments/assets/e33fb5c3-7dbd-40b2-bec5-471a465c7f4d" controls></video>
</p>

Add MCP capabilities to [Avante.nvim](https://github.com/yetone/avante.nvim) by following these steps:

## Add Tools To Avante

```lua
require("avante").setup({
    -- system_prompt as function ensures LLM always has latest MCP server state
    -- This is evaluated for every message, even in existing chats
    system_prompt = function()
        local hub = require("mcphub").get_hub_instance()
        return hub and hub:get_active_servers_prompt() or ""
    end,
    -- Using function prevents requiring mcphub before it's loaded
    custom_tools = function()
        return {
            require("mcphub.extensions.avante").mcp_tool(),
        }
    end,
})
```

- The `get_active_servers_prompt()` function adds the running MCP servers from MCP Hub to `system_prompt`
- The `mcp_tool()` function adds two custom tools `use_mcp_tool` and `access_mcp_resource` to avante.

## Configure Avante Integration

By default, MCP server prompts will be available as `/mcp:server_name:prompt_name` in avante chat.

```lua
require("mcphub").setup({
    extensions = {
        avante = {
            make_slash_commands = true, -- make /slash commands from MCP server prompts
        }
    }
})
```

![Image](https://github.com/user-attachments/assets/47086587-d10a-4749-a5df-3a562750010e)

## Tool Conflicts

MCP Hub's built-in Neovim server provides some basic development tools by default. 

![Image](https://github.com/user-attachments/assets/dbc0d210-2ccf-49f8-b1f5-58d868dc02c8)

Avante also provides built-in tools for file operations and terminal access. You need to disable either the MCP Hub's built-in tools or Avante's tools to avoid conflicts. If you prefer to use neovim server tools, you should disable the corresponding Avante tools to prevent duplication:

```lua
require("avante").setup({
    disabled_tools = {
        "list_files",    -- Built-in file operations
        "search_files",
        "read_file",
        "create_file",
        "rename_file",
        "delete_file",
        "create_dir",
        "rename_dir",
        "delete_dir",
        "bash",         -- Built-in terminal access
    },
})
```

## Auto-Approval

By default, whenever avante calls `use_mcp_tool` or `access_mcp_resource` tool, it shows a confirm dialog with tool name, server name and arguments.

![Image](https://github.com/user-attachments/assets/201a5804-99b6-4284-9351-348899e62467)

You can set `auto_approve` to `true` to automatically approve MCP tool calls without user confirmation.
```lua
require("mcphub").setup({
    -- This sets vim.g.mcphub_auto_approve to true by default (can also be toggled from the HUB UI with `ga`)
    auto_approve = true, 
})
```
This also sets `vim.g.mcphub_auto_approve` variable to `true`. You can also toggle this option in the MCP Hub UI with `ga` keymap. You can see the current auto approval status in the Hub UI.

![Image](https://github.com/user-attachments/assets/64708065-3428-4eb3-82a5-e32d2d1f98c6)


## Usage

1. Start a chat in Avante
2. All the tools, resources, templates from the running MCP servers will be added to system prompt along with `use_mcp_tool` and `access_mcp_resource` tools.
3. Avante will call `use_mcp_tool` and `access_mcp_resource` tools when necessary


