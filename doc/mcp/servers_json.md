# MCP Config File

MCPHub.nvim like other MCP clients uses a JSON configuration file to manage MCP servers. This `config` file is located at `~/.config/mcphub/servers.json` by default and supports real-time updates across all Neovim instances. You can set `config` option to a custom location. 

> [!NOTE]
> You can use a single config file for any MCP client like VSCode, Cursor, Cline, Zed etc as long as the config file follows the below structure. With MCPHub.nvim, `config` file can be safely added to source control as it supports **universal `${}` placeholder syntax** for environment variables and command execution across all configuration fields.
>
> [!TIP]
> Use the `global_env` option to inject environment variables into all MCP servers, instead of duplicating them in every server's `env` field.

## Manage Servers

Adding, editing, deleting and securing MCP servers in easy and intuitive with MCP Hub. You don't need to edit the `servers.json` file directly. Everything can be done right from the UI.

### From Marketplace

#### Browse, sort, filter , search from available MCP servers. 

![Image](https://github.com/user-attachments/assets/f5c8adfa-601e-4d03-8745-75180a9d3648)

#### One Click Install/Uninstall 

Choose from different install options:

![Image](https://github.com/user-attachments/assets/560bddda-e48d-488b-a9f8-7b188178914c)


### From Hub View

![Image](https://github.com/user-attachments/assets/1cb950da-2f7f-46e9-a623-4cc4b00cc3d0)

Add (`<A>`), edit (`<e>`), delete (`<d>`) MCP servers from the (`H`) Hub view.

## Basic Schema

The `config` file should have a `mcpServers` key. This contains `stdio` and `remote` MCP servers. There is also another top level MCPHub specific field `nativeMCPServers` to store any disabled tools, custom instructions etc that the plugin updates internally. See [Lua MCP Servers](/mcp/native/index) for more about Lua native MCP servers

```json
{
    "mcpServers": {
        // Add stdio and remote MCP servers here
    },
    "nativeMCPServers": { // MCPHub specific
        // To store disabled tools, custom instructions etc
    }
}
```

## Server Types

### Local (stdio) Servers

```json
{
    "mcpServers": {
        "local-server": {
            "command": "${MCP_BINARY_PATH}/server",
            "args": [
                "--token", "${API_TOKEN}",
                "--secret", "${cmd: op read op://vault/secret}"
            ],
            "env": {
                "API_TOKEN": "${cmd: aws ssm get-parameter --name /app/token --query Parameter.Value --output text}",
                "DB_URL": "postgresql://user:${DB_PASSWORD}@localhost/myapp",
                "DB_PASSWORD": "password123",
                "FALLBACK_VAR": null
            },
            "cwd": "/home/ubuntu/server-dir/"
        }
    }
}
```

##### Required fields:
- `command`: The executable to start the server (supports `${VARIABLE}` and `${cmd: command}`)

##### Optional fields: 
- `args`: Array of command arguments (supports `${VARIABLE}` and `${cmd: command}` placeholders)
- `env`: Environment variables with placeholder resolution and system fallback
- `cwd`: The current working directory for the MCP server process (supports `${VARIABLE}` and `${cmd: command}` placeholders)
- `dev`: Development mode configuration for auto-restart on file changes
- `name`: Display name that will be shown in the UI
- `description`: Short description about the server (useful when the server is disabled and `auto_toggle_mcp_servers` is `true`)

##### Universal `${}` Placeholder Syntax

**All fields** support the universal placeholder syntax:
- **`${ENV_VAR}`** - Resolves environment variables
- **`${cmd: command args}`** - Executes commands and uses output
- **`null` or `""`** - Falls back to `process.env`

Given `API_KEY=secret` in the environment:

| Example | Becomes | Description |
|-------|---------|-------------|
| `"API_KEY": ""` | `"API_KEY": "secret"` | Empty string falls back to `process.env.API_KEY` |
| `"API_KEY": null` | `"API_KEY": "secret"` | `null` falls back to `process.env.API_KEY` |
| `"AUTH": "Bearer ${API_KEY}"` | `"AUTH": "Bearer secret"` | `${}` Placeholder values are replaced | 
| `"TOKEN": "${cmd: op read op://vault/token}"` | `"TOKEN": "secret"` | Commands are executed and output used |
| `"HOME": "/home/ubuntu"` | `"HOME": "/home/ubuntu"` | Used as-is |

> ⚠️ **Legacy Syntax**: `$VAR` (args) and `$: command` (env) are deprecated but still supported with warnings. Use `${VAR}` and `${cmd: command}` instead.


#### `cwd` Example:

The `cwd` field is particularly useful when your MCP server needs to run in a specific directory context. Here's a practical example:

```json
{
    "mcpServers": {
        "project-server": {
            "command": "npm",
            "args": ["start"],
            "cwd": "/home/ubuntu/my-mcp-project/",
            "env": {
                "NODE_ENV": "development"
            }
        }
    }
}
```

**Use cases for `cwd`:**
- When the MCP server needs to access relative files in its project directory
- When using npm/yarn scripts that depend on being in the project root

> **Note**: The top-level `cwd` field sets the working directory for the server process itself, while `dev.cwd` (used in development mode) sets the directory for file watching. These serve different purposes and can be used together.


##### `dev` Development Mode

The `dev` field enables automatic server restarts when files change during development:

<p>
<video muted controls src="https://github.com/user-attachments/assets/af9654c2-e065-4f31-9bba-5c966284e221"></video>
</p>


```json
{
    "mcpServers": {
      "dev-server": {
        "command": "npx",
        "args": [
          "tsx",
          "path/to/src/index.ts"
        ],
        "dev": {
          "watch": [
            "src/**/*.ts",
            "package.json"
          ],
          "enabled": true,
          "cwd": "/path/to/dev-server/"
        }
      }
    }
}
```

###### Dev Configuration Options:

| Field | Required | Default | Description |
|-------|----------|---------|-------------|
| `cwd` | **Yes** | - | Absolute path to server's working directory |
| `watch` | No | `["**/*.js", "**/*.ts", "**/*.py","**/*.json"]` | Array of glob patterns to watch |
| `enabled` | No | `true` | Enable/disable dev mode |

When enabled, the server will automatically restart whenever files matching the watch patterns change in the specified directory. The system uses a 500ms debounce to prevent rapid restarts and ignores common directories like `node_modules`, `build`, `.git`, etc.

**Example use cases:**
- TypeScript/JavaScript MCP servers during development. Use `npx tsc index.ts` to bypass build step during development.
- Python servers with source code changes
- Configuration file updates that require restarts

### Remote Servers

MCPHub supports both `streamable-http` and `sse` remote servers.

```json
{
    "mcpServers": {
        "remote-server": {
            "url": "https://${PRIVATE_DOMAIN}/mcp",
            "headers": {
                "Authorization": "Bearer ${cmd: op read op://vault/api/token}",
                "X-Custom-Header": "${CUSTOM_VALUE}"
            }
        }
    }
}
```

##### Required fields:
- `url`: Remote server endpoint (supports `${VARIABLE}` and `${cmd: command}` placeholders)

##### Optional fields:
- `headers`: Authentication headers (supports `${VARIABLE}` and `${cmd: command}` placeholders)
- `name`: Display name that will be shown in the UI
- `description`: Short description about the server (useful when the server is disabled and `auto_toggle_mcp_servers` is `true`)

> **Note**: Remote servers use the same universal `${}` placeholder syntax as local servers. See the Universal Placeholder Syntax section above for full details.

## MCPHub Specific Fields

MCPHub adds several extra keys for each server automatically from the UI:

```json
{
    "mcpServers": {
        "example": {
            "disabled": false,
            "disabled_tools": ["expensive-tool"],
            "disabled_resources": ["resource://large-data"],
            "disabled_resourceTemplates": ["resource://{type}/{id}"],
            "autoApprove": ["safe-tool", "read-only-tool"],
            "custom_instructions": {
                "disabled": false,
                "text": "Custom instructions for this server"
            }
        }
    }
}
```

### Auto-Approval Configuration

![Image](https://github.com/user-attachments/assets/131bfed2-c4e7-4e2e-ba90-c86e6ca257fd)

![Image](https://github.com/user-attachments/assets/befd1d44-bca3-41f6-a99a-3d15c6c8a5f5)

The `autoApprove` field allows fine-grained control over which tools are automatically approved without user confirmation:

| Value | Behavior | Example |
|-------|----------|---------|
| `true` | Auto-approve all tools on this server | `"autoApprove": true` |
| `["tool1", "tool2"]` | Auto-approve only specific tools | `"autoApprove": ["read_file", "list_files"]` |
| `[]` or omitted | No auto-approval (show confirmation dialog) | `"autoApprove": []` |

**Notes:**
- Resources are always auto-approved by default (no explicit configuration needed)
- Auto-approval only applies to enabled servers and enabled tools
- You can toggle auto-approval from the UI using the `a` keymap on servers or individual tools
