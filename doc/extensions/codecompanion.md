# CodeCompanion Integration

<p>
<video muted controls src="https://github.com/user-attachments/assets/1a10ad50-5832-4627-bcc3-be49e7941105"></video>
</p>

Add MCP capabilities to [CodeCompanion.nvim](https://github.com/olimorris/codecompanion.nvim) by adding it as an extension.

## Features

- **Flexible Tool Access**: Multiple ways to use MCP tools - from broad `@mcp` access to granular individual tools
- **Server Groups**: Access all tools from a specific server (e.g., `@neovim`, `@github`, `@tree_sitter`)
- **Individual Tools**: Use specific tools with clear namespacing (e.g., `@neovim__read_file`, `@github__create_issue`)
- **Custom Tool Groups**: Create your own tool combinations for specific workflows
- **Resource Variables**: Utilize MCP resources as context variables using the `#` prefix (e.g., `#mcp:resource_name`)
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
        -- MCP Tools
        make_tools = true,              -- Make individual tools (@server__tool) and server groups (@server) from MCP servers
        show_server_tools_in_chat = true, -- Show individual tools in chat completion (when make_tools=true)
        add_mcp_prefix_to_tool_names = false, -- Add mcp__ prefix (e.g `@mcp__github`, `@mcp__neovim__list_issues`)
        show_result_in_chat = true,      -- Show tool results directly in chat buffer
        format_tool = nil,               -- function(tool_name:string, tool: CodeCompanion.Agent.Tool) : string Function to format tool names to show in the chat buffer
        -- MCP Resources
        make_vars = true,                -- Convert MCP resources to #variables for prompts
        -- MCP Prompts
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
Adds all available MCP servers to the system prompt and provides LLM with `@mcp` tool group which has `use_mcp_tool` and `access_mcp_resource` tools.
```
@{mcp} What files are in the current directory?
```

#### 2. Server Groups (when `make_tools = true`)
You can add all the enabled tools from a specific server with server groups. Unlike the `@mcp` group where all the running servers are converted and added to the system prompt, the tools added with server groups are pure function tools and hence depend on model support. The available groups depend on your connected MCP servers:

```
@{neovim} Read the main.lua file    # All tools from the neovim server will be added as function tools
@{github} Create an issue
@{fetch} Get this webpage
```

Server groups are automatically created based on your connected MCP servers when enabled via `make_tools`. Check your MCP Hub UI to see which servers you have connected.

MCPHub includes powerful [builtin servers](/mcp/builtin/neovim) like `@neovim` (file operations, terminal, LSP) and `@mcphub` (server management) that are always available.

#### 3. Individual Tools (when `make_tools = true`)
You can just provide a single tool from a server for fine-grained functionality. Tool names depend on your connected servers:
```
@{neovim__read_file} Show me the config file
@{fetch__fetch} Get this webpage content
@{github__create_issue} File a bug report
```

Use the MCP Hub UI or CodeCompanion's tool completion to discover available tools.

#### 4. Custom Tool Sets
Create your own tool combinations by mixing MCP tools with existing CodeCompanion tools:

Example configuration for custom tool groups:

```lua
require("codecompanion").setup({
  interactions = {
    chat = {
      tools = {
        groups = {
          ["github_pr_workflow"] = {
            description = "GitHub operations from issue to PR",
            tools = {
              -- File operations
              "neovim__read_multiple_files", "neovim__write_file", "neovim__edit_file",
              -- GitHub operations
              "github__list_issues", "github__get_issue", "github__get_issue_comments",
              "github__create_issue", "github__create_pull_request", "github__get_file_contents",
              "github__create_or_update_file",  "github__search_code"
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
@{github_pr_workflow} Fix this bug, create tests, and submit a PR with proper documentation
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
Fix diagnostics in the file #{mcp:neovim://diagnostics/buffer}
Analyze the current buffer #{mcp:neovim:buffer}
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


#### Fine-Grained Auto-Approval


For fine-grained control, configure auto-approval per server or per tool in your `servers.json`:

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

![Image](https://github.com/user-attachments/assets/131bfed2-c4e7-4e2e-ba90-c86e6ca257fd)

![Image](https://github.com/user-attachments/assets/befd1d44-bca3-41f6-a99a-3d15c6c8a5f5)

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

#### Function-Based Auto-Approval

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

#### Auto-Approval Priority

The system checks auto-approval in this order:
1. **Function**: Custom `auto_approve` function (if provided)
2. **Server-specific**: `autoApprove` field in server config
3. **Default**: Show confirmation dialog
