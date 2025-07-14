# Configuration

Please read the [getting started](/index) guide before reading this.

## Default Configuration

All options are optional with sensible defaults. See below for each option in detail.

```lua
{
    "ravitemer/mcphub.nvim",
    dependencies = {
        "nvim-lua/plenary.nvim",
    },
    build = "npm install -g mcp-hub@latest",  -- Installs `mcp-hub` node binary globally
    config = function()
        require("mcphub").setup({
            --- `mcp-hub` binary related options-------------------
            config = vim.fn.expand("~/.config/mcphub/servers.json"), -- Absolute path to MCP Servers config file (will create if not exists)
            port = 37373, -- The port `mcp-hub` server listens to
            shutdown_delay = 60 * 10 * 000, -- Delay in ms before shutting down the server when last instance closes (default: 10 minutes)
            use_bundled_binary = false, -- Use local `mcp-hub` binary (set this to true when using build = "bundled_build.lua")
            mcp_request_timeout = 60000, --Max time allowed for a MCP tool or resource to execute in milliseconds, set longer for long running tasks

            ---Chat-plugin related options-----------------
            auto_approve = false, -- Auto approve mcp tool calls
            auto_toggle_mcp_servers = true, -- Let LLMs start and stop MCP servers automatically
            extensions = {
                avante = {
                    make_slash_commands = true, -- make /slash commands from MCP server prompts
                }
            },

            --- Plugin specific options-------------------
            native_servers = {}, -- add your custom lua native servers here
            builtin_tools = {
                edit_file = {
                    parser = {
                        track_issues = true,
                        extract_inline_content = true,
                    },
                    locator = {
                        fuzzy_threshold = 0.8,
                        enable_fuzzy_matching = true,
                    },
                    ui = {
                        go_to_origin_on_complete = true,
                        keybindings = {
                            accept = ".",
                            reject = ",",
                            next = "n",
                            prev = "p",
                            accept_all = "ga",
                            reject_all = "gr",
                        },
                    },
                },
            },
            ui = {
                window = {
                    width = 0.8, -- 0-1 (ratio); "50%" (percentage); 50 (raw number)
                    height = 0.8, -- 0-1 (ratio); "50%" (percentage); 50 (raw number)
                    align = "center", -- "center", "top-left", "top-right", "bottom-left", "bottom-right", "top", "bottom", "left", "right"
                    relative = "editor",
                    zindex = 50,
                    border = "rounded", -- "none", "single", "double", "rounded", "solid", "shadow"
                },
                wo = { -- window-scoped options (vim.wo)
                    winhl = "Normal:MCPHubNormal,FloatBorder:MCPHubBorder",
                },
            },
            on_ready = function(hub)
                -- Called when hub is ready
            end,
            on_error = function(err)
                -- Called on errors
            end,
            log = {
                level = vim.log.levels.WARN,
                to_file = false,
                file_path = nil,
                prefix = "MCPHub",
            },
        })
    end
}
```

## Binary `mcp-hub` Options

On calling `require("mcphub").setup()`, MCPHub.nvim starts the `mcp-hub` process with the given arguments. Internally the default command looks something like:

```bash
mcp-hub --config ~/.config/mcphub/servers.json --port 37373 --auto-shutdown --shutdown-delay 600000 --watch
```

We can configure how the `mcp-hub` process starts and stops as follows:


### config

Default: `~/.config/mcphub/servers.json`

Absolute path to the MCP Servers configuration file. The plugin will create this file if it doesn't exist. See [servers.json](/mcp/servers_json) page to see how `servers.json` should look like, how to safely add it to source control and more


### port

Default: `37373`

The port number that the `mcp-hub`'s express server should listen on. MCPHub.nvim sends curl requests to `http://localhost:37373/` endpoint to manage MCP servers. We first check if `mcp-hub` is already running before trying to start a new one. 

### server_url
    
Default: `nil`

By default, we send curl requests to `http://localhost:37373/` to manage MCP servers. However, in cases where you want to run `mcp-hub` on another machine in your local network or remotely you can override the endpoint by setting this to the server URL e.g `http://mydomain.com:customport` or `https://url_without_need_for_port.com`

### shutdown_delay

Default: `600000` (10 minutes)

Time in milliseconds to wait before shutting down the `mcp-hub` server when the last Neovim instance closes. The `mcp-hub` server stays up for 10 minutes after exiting neovim. On entering, MCPHub.nvim checks for the running server and connects to it. This makes the MCP servers readily available. You can set it to a longer time to keep `mcp-hub` running. 

<p>
<video src="https://github.com/user-attachments/assets/c3a93e22-0e0a-46ca-96c1-d060076abd59" controls> </video>
</p>

### use_bundled_binary

Default: `false`

Uses local `mcp-hub` binary. Enable this when using `build = "bundled_build.lua"` in your plugin configuration.


### mcp_request_timeout

Default: `60000` (1 minute)

Maximum time allowed for a MCP tool or resource or prompt to execute in milliseconds. If exceeded, an McpError with code `RequestTimeout` will be raised. Set longer if you have longer running tools. 

### cmd, cmdArgs

Default: `nil`

Internally `cmd` points to the `mcp-hub` binary. e.g for global installations it is `mcp-hub`. When `use_bundled_binary` is `true` it is `~/.local/share/nvim/lazy/mcphub.nvim/bundled/mcp-hub/node_modules/mcp-hub/dist/cli.js`. You can set this to something else so that MCPHub.nvim uses `cmd` and `cmdArgs` to start the `mcp-hub` server. You can clone the `mcp-hub` repo locally using `gh clone ravitemer/mcp-hub` and provide the path to the `cli.js` as shown below:

```lua
require("mcphub").setup({
    cmd = "node",
    cmdArgs = {"/path/to/mcp-hub/src/utils/cli.js"},
})
```

See [Contributing](https://github.com/ravitemer/mcphub.nvim/blob/main/CONTRIBUTING.md) guide for detailed development setup.

## Chat-Plugin Related Options

### auto_approve

Default: `false`

By default when the LLM calls a tool or resource on a MCP server, we show a confirmation window like below.

![Image](https://github.com/user-attachments/assets/201a5804-99b6-4284-9351-348899e62467)

#### Boolean Auto-Approval

Set it to `true` to automatically approve all MCP tool calls without user confirmation:

```lua
require("mcphub").setup({
    auto_approve = true, -- Auto approve all MCP tool calls
})
```

This also sets `vim.g.mcphub_auto_approve` variable to `true`. You can toggle this option in the MCP Hub UI with `ga` keymap. You can see the current auto approval status in the Hub UI.

![Image](https://github.com/user-attachments/assets/64708065-3428-4eb3-82a5-e32d2d1f98c6)

#### Function-Based Auto-Approval

For maximum control, provide a function that decides approval based on the specific tool call:

```lua
require("mcphub").setup({
    auto_approve = function(params)
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

#### Server-Level Auto-Approval

For fine-grained control per server or tool, configure auto-approval using the `autoApprove` field in your `servers.json`. You can also toggle auto-approval from the Hub UI using the `a` keymap on individual servers or tools. See [servers.json configuration](/mcp/servers_json#auto-approval-configuration) for detailed examples and configuration options.

#### Auto-Approval Priority

The system checks auto-approval in this order:
1. **Function**: Custom `auto_approve` function (if provided)
2. **Server-specific**: `autoApprove` field in server config
3. **Default**: Show confirmation dialog

### auto_toggle_mcp_servers

Default: `true`

Allow LLMs to automatically start and stop MCP servers as needed. Disable to require manual server management. The following demo shows avante auto starting a disabled MCP server to acheive it's objective. See [discussion](https://github.com/ravitemer/mcphub.nvim/discussions/88) for details.

<p>
<video src="https://github.com/user-attachments/assets/2e05344f-0bb1-4999-810b-445ec37aa66f" controls></video>
</p>


### extensions

Default:

```lua
{
    extensions = {
        avante = {
            enabled = true,
            make_slash_commands = true
        }
    }
}
```


[Avante](https://github.com/yetone/avante.nvim) integration options:
- `make_slash_commands`: Convert MCP server prompts to slash commands in Avante chat
- Please visit [Avante](/extensions/avante) for full integration documentation

Also see [CodeCompanion](/extensions/codecompanion), [CopilotChat](/extensions/copilotchat) pages for detailed setup guides.


## Plugin Options

### native_servers

Default: `{}`

Define custom Lua native MCP servers that run directly in Neovim without external processes. Each server can provide tools, resources, and prompts. Please see [native servers guide](/mcp/native/index) to create MCP Servers in lua.

### builtin_tools

Default:

```lua
{
    builtin_tools = {
        edit_file = {
        },
    },
}
```

Configuration options for MCPHub's builtin tools like `edit_file` tool. View complete [Builtin Tools Documentation](/mcp/builtin/) for all available tools and their configuration options.

### ui

Default:

```lua
{
    ui = {
        window = {
            width = 0.85, -- 0-1 (ratio); "50%" (percentage); 50 (raw number)
            height = 0.85, -- 0-1 (ratio); "50%" (percentage); 50 (raw number)
            align = "center", -- "center", "top-left", "top-right", "bottom-left", "bottom-right", "top", "bottom", "left", "right"
            border = "rounded", -- "none", "single", "double", "rounded", "solid", "shadow"
            relative = "editor",
            zindex = 50,
        },
        wo = { -- window-scoped options (vim.wo)
            winhl = "Normal:MCPHubNormal,FloatBorder:MCPHubBorder",
        },
    },
}
```

Controls the appearance and behavior of the MCPHub UI window:
- `width`: Window width (0-1 for ratio, "50%" for percentage, or raw number)
- `height`: Window height (same format as width)
- `align`: Window alignment position. Options:
  - `"center"`: Center the window (default)
  - `"top-left"`, `"top-right"`, `"bottom-left"`, `"bottom-right"`: Corner positions
  - `"top"`, `"bottom"`: Top/bottom edge, centered horizontally
  - `"left"`, `"right"`: Left/right edge, centered vertically
- `relative`: Window placement relative to ("editor", "win", or "cursor")
- `zindex`: Window stacking order
- `border`: Border style ("none", "single", "double", "rounded", "solid", "shadow")

### on_ready

Default: `function(hub) end`

Callback function executed when the MCP Hub server is ready and connected. Receives the hub instance as an argument.


### on_error

Default: `function(err) end`

Callback function executed when an error occurs in the MCP Hub server. Receives the error message as an argument.


### log

Default:
```lua
{
    level = vim.log.levels.WARN,
    to_file = false,
    file_path = nil,
    prefix = "MCPHub"
}
```

Logging configuration options:
- `level`: Log level (vim.log.levels.ERROR, WARN, INFO, DEBUG, TRACE)
- `to_file`: Whether to write logs to file
- `file_path`: Custom log file path
- `prefix`: Prefix for log messages






