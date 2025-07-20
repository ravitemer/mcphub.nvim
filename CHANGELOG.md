# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [6.1.0] - 2025-07-20

### Added

- **VS Code Configuration Compatibility**: Support for `.vscode/mcp.json` format (#209)
  - Support for `"servers"` key alongside existing `"mcpServers"` key
  - VS Code variable syntax: `${env:VARIABLE}`, `${workspaceFolder}`, `${userHome}`, `${pathSeparator}`
  - VS Code input variables via `global_env`: `${input:variable-id}` support
  - Seamless migration: existing VS Code configs work directly

- **JSON5 Support**: Enhanced config parsing with comments and trailing commas (#210)
  - Custom `json_decode` option for JSON5 parser integration
  - Comprehensive error messaging with setup guidance for JSON5
  - Support for lua-json5 parser integration

- **Configuration Enhancements**:
  - `CWD` variable resolution in MCP server configs
  - Lualine integration with global variables API for lazy-loading support
  - Enhanced error handling during config file watching

### Fixed

- **Windows Compatibility**: Improved home directory detection for Windows users
- **Config Error Handling**: Better error management during config file watching
- **Marketplace Cleanup**: Removed legacy AI installation logic


## [6.0.0] - 2025-07-18

### Added

- ** Workspace-Aware MCP Hub**: project-local configuration support (#148, #183, #196, #200)
  - **Smart Project Detection**: Automatically detects project boundaries using `.mcphub/servers.json`, `.vscode/mcp.json`, `.cursor/mcp.json`
  - **Isolated Hub Instances**: Each workspace gets its own mcp-hub process with unique ports (40000-41000 range)
  - **Configuration Merging**: Project configs automatically override global settings while preserving global servers
  - **Automatic Switching**: Seamlessly switches between workspace hubs on directory changes (`DirChanged` events)
  - **Dynamic Port Allocation**: Hash-based port generation with conflict resolution and custom port assignment support

- ** Global Environment Variables**: Universal environment injection for all MCP servers (#183)
  - **Flexible Configuration**: Support for both table and function-based global_env configuration
  - **Context-Aware Variables**: Function receives workspace context (port, config files, workspace mode) 
  - **Mixed Format Support**: Array-style (`"VAR"`) and hash-style (`KEY = "value"`) entries
  - **Automatic Resolution**: Environment variables resolved when hub starts with project context

- **🎨 Enhanced UI Experience**: Complete workspace management interface
  - **Active Hubs Section**: View and manage all running workspace hub instances
  - **Grouped Server Display**: Servers organized by config source (Global vs Project) with visual indicators
  - **Multi-Config Editor**: Tab-based interface for editing different config files (global and project)
  - **Workspace Actions**: Expand/collapse details, kill processes, change directories, view configuration files

### Enhanced

- **Directory Change Handling**: Proper hub switching when changing directories in Neovim
- **Config File Watching**: Enhanced file watching to handle multiple configuration sources
- Some common expected keymaps like `<Cr>`, `o` and `<Esc>` work along with the `l` and `k` keys

### Fixed

- **Multi-Project Isolation**: Solves the fundamental issue of MCP servers working in wrong project directories
- **Environment Variable Access**: Addresses user session variables (like `DBUS_SESSION_BUS_ADDRESS`) not being available to MCP servers

### Migration Guide

Existing configurations work without changes. To enable workspace features:

```lua
require("mcphub").setup({
  workspace = {
    enabled = true, -- Default: true
    look_for = { ".mcphub/servers.json", ".vscode/mcp.json", ".cursor/mcp.json" },
    reload_on_dir_changed = true,
    port_range = { min = 40000, max = 41000 },
    get_port = nil, -- Optional custom port function
  },
  global_env = {
    "DBUS_SESSION_BUS_ADDRESS", -- Array-style: uses os.getenv()
    API_KEY = os.getenv("API_KEY"), -- Hash-style: explicit value
  }
})
```


## [5.13.0] - 2025-07-14

### Added

- **Granular Tool Access for CodeCompanion**: Individual MCP servers and tools now available as separate CodeCompanion function tools
  - Server groups (e.g., `@github`, `@neovim`) and individual tools (e.g., `@github__create_issue`)
  - Per-tool auto-approval control from Hub UI
  - Custom tool combinations through CodeCompanion groups
  - Eliminates system prompt pollution for better model performance

- **Advanced `edit_file` Tool**: Interactive SEARCH/REPLACE block system with real-time diff preview
  - Intelligent fuzzy matching and comprehensive feedback for LLM learning
  - Configurable keybindings and behavior through `builtin_tools.edit_file` config
  - Extensive test suite with 3000+ test cases

### Enhanced

- **JSON Formatting**: Added `jq` support for prettier configuration file formatting
- **MCP Tool Prompts**: Improved markdown formatting and structure for better LLM consumption

### Fixed

- **Avante Integration**: Fixed tool input formatting for Gemini model compatibility with `use_ReAct_prompt`

## [5.12.0] - 2025-07-09

### Enhanced
- **MCP Registry Migration**: Updated to support mcp-hub v4.0.0 with new MCP Registry system
  - Improved reliability with decentralized registry system (https://github.com/ravitemer/mcp-registry)
  - Enhanced server metadata with comprehensive installation instructions
  - Better caching system with 1-hour TTL for frequent updates

### Changed

- Updated mcp-hub dependency to v4.0.0 for new registry system
- Marketplace now uses MCP Registry instead of Cline marketplace API
- Enhanced error handling for marketplace operations

## [5.11.1] - 2025-07-08

### Added

- **`cwd` field support for stdio servers**: 
  - Added `cwd` field to `MCPServerConfig` type definition
  - Added validation for `cwd` field in server configuration
  - Updated documentation with examples and use cases

## [5.11.0] - 2025-06-26

### Added

- **XDG Base Directory Specification Support**: Migrated from hardcoded ~/.mcp-hub paths to XDG-compliant directories
  - Marketplace cache now uses XDG data directory (`~/.local/share/mcp-hub/cache`)
  - Logs now use XDG state directory (`~/.local/state/mcp-hub/logs`)
  - OAuth storage now uses XDG data directory (`~/.local/share/mcp-hub/oauth`)
  - Backward compatibility maintained for existing ~/.mcp-hub installations
  - New XDG paths utility module with automatic fallback logic

### Enhanced

- Updated documentation to reflect new XDG-compliant path structure
- Improved file organization following Linux filesystem standards


## [5.10.0] - 2025-06-24

### Added

- Integrated support for MCP Hub's unified endpoint feature
  - Added documentation for the dual-interface approach (management + MCP endpoint)
  - Added configuration examples for unified endpoint usage

## [5.9.0] - 2025-06-24

### Added

- Improved OAuth flow for remote/headless servers
  - New auth popup UI with clear instructions
  - Manual callback URL support for headless environments
  - Auto-closing popup on successful authorization
  - Better error handling and validation
  - Tab navigation between info and input windows

### Changed

- Updated mcp-hub dependency to v3.5.0 for improved OAuth support

## [5.8.0] - 2025-06-23

### Added

- Function-based auto-approval system for MCP tool calls (#173)
  - `auto_approve` can now be a function that receives tool call parameters
  - Function receives `server_name`, `tool_name`, `arguments`, `action`, `uri`, and `is_auto_approved_in_server`
  - Return `true` to approve, `false` to prompt, or `string` to deny with custom error message
  - Enables sophisticated approval logic based on tool arguments and context
  - Backward compatible with existing boolean and server-level configuration

### Changed

- **Breaking**: Removed automatic `vim.g.codecompanion_auto_tool_mode` checking in CodeCompanion integration
  - Users can achieve the same behavior by checking this variable in their custom `auto_approve` function
  - Simplifies auto-approval logic and removes plugin-specific dependencies
- Refactored extension system for better modularity and type safety
- Updated auto-approval priority: function-based → server config → user prompt
- Enhanced hub startup logic with better state management and restart handling

### Documentation

- Added comprehensive function-based auto-approval examples and parameter documentation
- Updated integration guides for Avante and CodeCompanion with new auto-approval patterns
- Added real-world examples for GitHub access control and project-scoped operations

## [5.7.5] - 2025-06-18

### Fixed

- Fixed nested placeholder resolution in environment variables not working correctly (#170)

### Changed

- Updated mcp-hub dependency to v3.4.5 for improved nested placeholder resolution

## [5.7.4] - 2025-06-16

### Added

- Added vim.g.mcphub configuration support for package manager friendly configuration (#167)
- Auto-setup logic for vim.g.mcphub in plugin/mcphub.lua
- Comprehensive welcome screen for not_started state with configuration examples
- Support for both vim.g.mcphub and traditional setup() approaches
- Package manager friendly configuration (NixOS, rocks.nvim)
- Added devShell with pandoc and stylua for development (#165)

### Changed

- Moved MCPHub command creation to plugin file with on-demand UI creation
- Decoupled command creation from setup() function for better initialization
- Maintain full backward compatibility with existing setup approaches

### Fixed

- Show better error messages with config errors (#163)
- Fire tool call result on MCPHubToolEnd events

## [5.7.3] - 2025-06-13

### Changed

- Added proper plugin initialization with highlight setup
- Refactored highlights to use theme-linked groups instead of custom colors (#158)
- configurable builtin replace_in_file tool keymaps (#159)

### Fixed

- Fixed env resolution strict mode preventing server startups

## [5.7.2] - 2025-06-11

### Fixed

- Fixed `${cmd: ...}` placeholders not working in remote server configs without an `env` field
- Commands can now be executed in any config field (url, headers, args, command), not just env
- Better handling of circular dependencies in environment variable resolution

## [5.7.1] - 2025-06-10

### Changed

- Server configuration now supports `${ENV_VAR}` and `${cmd: command args}` syntax in all fields
- Updated mcp-hub dependency to v3.4.0 for universal `${}` placeholder syntax support
- Updated documentation to reflect new universal placeholder syntax features
- Better log avante tool calls

## [5.7.0] - 2025-06-05

### Added

- Use `name` field from MCP server config in the UI (#152)

### Fixed

- Bug when server has only resource templates (#147)
- Validate MCP server config fields (#149)
- Show error message on setup failed
- Error concatenation in checkhealth (#153)
- Fallback to curl to fetch marketplace data

### Changed

- Use pname in nix-flake (#146)
- Updated sponsors in README

## [5.6.1] - 2025-05-30

## Fixed

- Tool list changed event not updating in the UI

### Changed

- Updated mcp-hub dependency to v3.3.1 for improved subscription event handling

## [5.6.0] - 2025-05-28

### Added

- Fine-grained auto-approval support for servers and tools
- `autoApprove` field in server config (boolean or string array)
- `a` keymap to toggle auto-approval on servers and individual tools
- Visual indicators for auto-approval status in UI
- Support for editing native server config fields from UI

### Changed

- Resources are now always auto-approved by default
- Enhanced confirmation prompt UI

### Fixed

- Nix flake now includes plenary dependency

## [5.5.0] - 2025-05-26

### Added

- Dev mode support for automatic MCP server restart on file changes during development
- Documentation for `dev` configuration field with watch patterns and working directory
- Enhanced development workflow with hot reload capabilities

### Changed

- Updated mcp-hub dependency to v3.3.0 for dev mode support

## [5.4.0] - 2025-05-24

### Added

- Beautiful tool confirmation dialog with floating window
- Syntax highlighting for parameters in confirmation dialog
- Support for multiline strings in tool confirmations

### Fixed

- Tool confirmation dialog not displaying properly (#131)
- Screen flashing issue during confirmation prompts

## [5.3.1] - 2025-05-24

### Added

- For long running tools or prompts or resources, we can now set `mcp_request_timeout` in ms to wait for the execution to finish. Defaults to 60s.

### Changed

- Updated mcp-hub dependency version

## [5.3.0] - 2025-05-22

### Added

- Added image support in CodeCompanion extension

### Fixed

- Fixed empty tool responses handling in extensions
- Fixed multiline input box not opening while testing capabilities
- Fixed MCP server stderr output being incorrectly logged as warning
- Fixed padding issues when no servers are present
- Fixed editor not opening while adding servers from marketplace detail view
- Fixed type issues by setting strict to false
- Fixed deprecated replace_headers usage (fixes #122)

### Changed

- Complete overhaul of documentation with new GitHub pages website
  - Updated sponsors section
  - Migrated content from wiki
- Added more TypeScript type definitions for better code quality
- Updated mcp-hub dependency version

## [5.2.0] - 2025-05-06

### Added

- Support for `$: cmd arg1 arg2` syntax in env config to execute shell commands to resolve env values
- E.g

```json
{
  "command": "npx",
  "args": ["-y", "@modelcontextprotocol/server-everything"],
  "env": {
    "MY_ENV_VAR": "$: cmd:op read op://mysecret/myenvvar"
  }
}
```

## [5.1.0] - 2025-05-06

### Changed

- Improved UX for tool execution results in CodeCompanion chat
  - Better formatted success messages showing tool name
  - Modified tool output display for clearer feedback
  - Silent error throwing for better UX in chat plugins

### Fixed

- Enhanced error handling and propagation for MCP tool execution
  - Consistent error handling across Avante and CodeCompanion
- Fixed bugs in first-time config creation
  - Ensure config directory exists before file creation
  - Fixed default configuration JSON encoding (empty dict instead of array)
- Enhanced server deletion UX by replacing confirm with select menu

## [5.0.1] - 2025-05-03

### Fixed

- Marketplace refetches if catalog empty
- Fixed parallel tool calls returning first tool's output

## [5.0.0] - 2025-04-29

### Breaking Changes

In view of v15 release of codecompanion, we have made some breaking changes to the mcphub.nvim plugin.

- Now mcphub provides `@mcp` as both an xml tool (when using `has-xml-tools` branch of codecompanion) as well as a function tool (with `main` branch of codecompanion) automatically based on the codecompanion branch.

1. 🚨 You need to remove the old mcp tool entry from codecompanion.config.strategies.chat.tools

```lua
require("codecompanion").setup({
 -- other codecompanion config
  strategies = {
    chat = {
       tools = {
     -- Remove old mcp tool which will be auto added as a tool group with two individual tools.
      --   ["mcp"] = {
      --     callback = function()
      --       return require("mcphub.extensions.codecompanion")
      --     end,
      --     description = "Call tools and resources from MCP Servers",
      --   },
     },
    },
  },
})
```

2. codecompanion extension is now more streamlined in one place using the codecompanoin's extensions api.

```lua
require("codecompanion").setup({
--other config
extensions = {
  mcphub = {
    callback = "mcphub.extensions.codecompanion",
    opts = {
      make_vars = true,
      make_slash_commands = true,
      show_result_in_chat = true,
    },
  },
 },
})

```

- The `@mcp` tool is split into two separate tools `use_mcp_tool` and `access_mcp_resource`
- mcphub.config.extensions.codecompanion is deprecated as the options are now declared at codecompanion extension itself.

## [4.11.0] - 2025-04-25

### Added

- Added support for ${} placeholder values in env and headers (#100)
- Modified "R" key to kill and restart mcp-hub to reload latest process.env (#98)

### Fixed

- Fixed notifications persisting from stopped servers
- Fixed false positive modified triggers for servers with env field containing falsy values
- Fixed system prompt to ensure exact server names are used

### Documentation

- Updated lualine documentation
- Updated README with ${} placeholder support
- Updated TODOs

## [4.10.0] - 2025-04-23

### Added

- Full support for MCP 2025-03-26 specification
- Streamable-HTTP transport support with OAuth PKCE flow
- SSE fallback transport for remote servers
- Auto-detection of streamable-http/SSE transport
- Auto OAuth authorization for remote servers
- Comprehensive capabilities matrix in documentation

### Documentation

- Improved installation instructions
- Enhanced server configuration examples
- Complete rewrite of features section
- Added official spec references
- Clarified transport protocols

## [4.9.0] - 2025-04-21

### Added

- Can add servers: Press 'A' in main view to open editor and paste server config
- Can edit servers: Press 'e' to modify existing server configurations
- Can remove servers: Press 'd' to delete servers
- Added manual installation support from marketplace

## [4.8.0] - 2025-04-14

### Added

- Added `toggle_mcp_server` tool to mcphub native server

  - Moved mcphub related resources from neovim server into mcphub server
  - Added toggle_mcp_server tool that toggles a MCP server and returns the server schema when enabled
  - We now do not need to pass the entire prompt of all servers upfront. As long as we have servers in our config LLM can see them. With disabled servers we send the server name and description if any so that LLM can dynamically start and stop servers
  - Added description to MCP Servers (so that LLM has an overview of the server to pick which server to enable when we send disabled servers as well)
    - Usual MCP Servers do not have any description
    - Description will be attached to MCP Servers that are added from Marketplace
    - You can also add description to native servers

- Enhanced server prompts with disabled servers support
  - Previously, disabled servers were hidden from system prompts
  - Now includes both connected and disabled servers in system prompts with clear section separation

### Changed

- Improved CodeCompanion integration for better LLM interactions
  - Enabled show_result_in_chat by default to provide better visibility of tool responses
  - Whenever there are #Headers in the response when using mcp tools, we replace # with > because showing result in chat gives user more control and currently the # are not making it possible
  - Pseudocode examples seems to produce better results even for xml based tools
  - Renamed `arguments` parameter to `tool_input` in XML for clearer structure

### Fixed

- Fixed 'gd' preview rendering to properly highlight markdown syntax

## [4.7.0] - 2025-04-13

### Added

- Complete multi-instance support

  - Complete support for opening multiple neovim instance at a time
  - MCP Hubs in all neovim instances are always in sync (toggling something or change changing config in one neovim will auto syncs other neovim instances)
  - Changed lualine extension to adapt to these changes

- Added file watching for servers.json

  - Watches config file and updates necessary servers. No need to exit and enter neovim or press "R" to reload any servers after your servers.json file is changed.
  - Config changes apply instantly without restart
  - Changes sync across all running instances
  - Smart reload that only updates affected servers

- Added smart shutdown with delay

  - Previoulsy when we exit neovim mcphub.nvim stops the server and when we enter neovim it starts the server.
  - We can now set shutdown_delay (in millisecond) to let the server wait before shutdown. If we enter neovim again within this time it will cancel the timer.
  - Defaults to 10 minutes. You can set this to as long as you want to make it run essentially as a systemd service

- Improved UI navigation
  - Added vim-style keys (hjkl) for movement

### Changed

- Updated MCP Hub to v3.0.0 for multi-instance support

* Auto-resize windows on editor resize

## [4.6.1] - 2025-04-10

### Added

- In cases where mcp-hub server is hosted somewhere, you can set `config.server_url` e.g `http://mydomain.com:customport` or `https://url_without_need_for_port.com`
- `server_url` defaults to `http://localhost:{config.port}`

## [4.6.0] - 2025-04-09

### Added

- Added support for Windows platform
- Added configurable window options (#68)
- Added examples to servers prompt for function based tools to improve model responses

### Fixed

- Fixed incorrect boolean evaluation in add_example function
- Fixed async vim.ui.input handling for prompts (#71)
- Fixed config file creation when not present

### Documentation

- Improved native server LLM guide
- Enhanced CodeCompanion documentation
- Updated MCP server configuration options
- Fixed indentation in default config examples

## [4.5.0] - 2025-04-08

### Added

- Added support for Avante slash commands
  - Prompts from MCP servers will be available as `/mcp:server_name:prompt_name` in Avant chat
  - When slash command is triggered, messages from the prompt with appropriate roles will be added to chat history.
  - Along with MCP Server prompt, you can also create your own prompts with mcphub.add_prompt api. ([Native Servers](https://github.com/ravitemer/mcphub.nvim/wiki/Weather-Server))
  - You can disable this with `config.extensions.avante.make_slash_commands = false` in the setup.
- Avante mcp_tool() return two separate `use_mcp_tool` and `access_mcp_resource` tools which should make it easy for models to generate proper schemas for tool calls. (No need to change anything in the config)

## [4.4.0] - 2025-04-05

### Added

- Added support for SSE (Server-Sent Events) MCP servers
- Updated documentation with SSE server configuration examples
- Updated required mcp-hub version to 2.1.0 for SSE support

## [4.3.0] - 2025-04-04

### Added

- Added support for MCP server prompts capability
- Added prompts as /slash_commands in CodeCompanion integration
- Added audio content type support for responses
- Added native server prompts support with role-based chat messages

### Changed

- Updated MCP Hub dependency to v2.0.1
- Modified API calls to use new endpoint format where server name is passed in request body
- Changed prompt rendering in base capabilities to support new format
- Updated documentation with new prompts and slash commands features

### Fixed

- Fixed bug when viewing system prompt in UI
- Fixed server logs re-rendering other views while still connected

## [4.2.0] - 2025-04-02

### Deprecated

- Deprecated Avante's auto_approve_mcp_tool_calls setting in favor of global config.auto_approve
- Deprecated CodeCompanion's opts.requires_approval setting in favor of global config.auto_approve

### Added

- Added global auto-approve control through vim.g.mcphub_auto_approve and config.auto_approve
- Added UI toggle (ga) for auto-approve in main view
- Added auto-approve support in write_file tool while maintaining editor visibility

### Changed

- Unified auto-approve handling across the plugin
- Moved auto-approve settings from extensions to core config
- Updated Avante and CodeCompanion extensions to use global auto-approve setting
- Updated documentation to reflect new auto-approve configuration

## [4.1.1] - 2025-04-02

### Changed

- Updated mcp-hub dependency to v1.8.1 for the new restart endpoint (fixes #49)

## [4.1.0] - 2025-04-01

### Added

- Added explicit instructions for MCP tool extensions
  - Improved parameter validation and error messages
  - Better documentation of required fields
  - Enhanced type checking for arguments

### Changed

- Changed CodeCompanion show_result_in_chat to false by default
- Disabled replace_in_file tool in native Neovim server

## [4.0.0] - 2025-04-01

### Added

- Added explicit instructions for MCP tool extensions
  - Improved parameter validation and error messages
  - Better documentation of required fields
  - Enhanced type checking for arguments

### Fixed

- Changed CodeCompanion show_result_in_chat to false by default
- Disabled replace_in_file tool in native Neovim server

### Added

- Zero Configuration Support

  - Default port to 37373
  - Default config path to ~/.config/mcphub/servers.json
  - Auto-create config file with empty mcpServers object
  - Works out of the box with just require("mcphub").setup({})

- Installation Improvements

  - Added bundled installation option for users without global npm access
  - Added `build = "bundled_build.lua"` alternative
  - Auto-updates with plugin updates
  - Flexible cmd and cmdArgs configuration for custom environments

- UI Window Customization

  - Configurable width and height (ratio, percentage, or raw number)
  - Border style options
  - Relative positioning
  - Z-index control

- Lualine Integration

  - Dynamic status indicator
  - Server connection state
  - Active operation spinner
  - Total connected servers display

- Native MCP Servers Support

  - Write once, use everywhere design
  - Clean chained API for tools and resources
  - Full URI-based resource system with templates
  - Centralized lifecycle management
  - Auto-generate Native MCP servers with LLMs

- Built-in Neovim MCP Server

  - Common utility tools and resources
  - Configurable tool enablement
  - Interactive file operations with diff view
  - Improved write_file tool with editor integration

- MCP Resources to Chat Variables
  - Real-time variable updates
  - CodeCompanion integration
  - LSP diagnostics support

### Changed

- Enhanced UI features

  - Added syntax highlighting for config view and markdown text
  - Added multiline input textarea support with "o" keymap
  - Improved Hub view with breadcrumb preview
  - Updated Help view

- Improved Integration Features
  - Configure auto-approve behavior in Avante
  - Configure tool call results in CodeCompanion
  - Enhanced tool and resource handling

## [3.5.0] - 2025-03-19

### Added

- Support for configurable custom instructions per MCP server
  - Add, edit, and manage custom instructions through UI
  - Enable/disable custom instructions per server
  - Instructions are included in system prompts
  - Enhanced validation for custom instructions config

## [3.4.2] - 2025-03-19

### Changed

- Improved marketplace search and filtering experience
  - Enhanced search ranking to prioritize title matches
  - Simplified server details view to show "Installed" status
  - Added auto-focus to first interactive item after search/filter
  - Fixed loading state handling in server details

## [3.4.1] - 2025-03-18

### Removed

- Removed shutdown_delay option and related code (#20)
  - Simplified server lifecycle management
  - Updated documentation to reflect changes
  - Cleaned up configuration examples

## [3.4.0] - 2025-03-18

### Added

- Added dynamic colorscheme adaptation for UI highlights
  - Highlights now automatically update when colorscheme changes
  - Uses semantic colors from current theme
  - Falls back to sensible defaults when colors not available

### Changed

- Changed special key highlighting to use Special group instead of Identifier

## [3.3.1] - 2025-03-16

### Fixed

- Fixed Avante MCP server installer implementation to properly handle chat history and prompts

## [3.3.0] - 2025-03-15

### Added

- Marketplace integration
  - Browse available MCP servers with details and stats
  - Sort, filter by category, and search servers
  - View server documentation and installation guides
  - One-click installation via Avante/CodeCompanion
- Server cards and detail views
  - Rich server information display
  - GitHub stats integration
  - README preview support
- Automatic installer system
  - Support for Avante and CodeCompanion installations
  - Standardized installation prompts
  - Intelligent server configuration handling

### Changed

- Updated MCP Hub version requirement to 1.7.1
- Enhanced UI with new icons and visual improvements
- Improved server state management and configuration handling

## [3.2.0] - 2025-03-14

### Added

- Added async tool support to Avante extension
  - Updated to use callbacks for async operations

## [3.1.0] - 2025-03-13

### Changed

- Made CodeCompanion extension fully asynchronous
  - Updated to support cc v13.5.0 async function commands
  - Enhanced tool and resource callbacks for async operations
  - Improved response handling with parse_response integration

## [3.0.0] - 2025-03-11

### Breaking Changes

- Replaced return_text parameter with parse_response in tool/resource calls
  - Now returns a table with text and images instead of plain text
  - Affects both synchronous and asynchronous operations
  - CodeCompanion and Avante integrations updated to support new format

### Added

- Image support for tool and resource responses
  - Automatic image caching system (temporary until Neovim exits)
  - File URL generation for image previews using gx
  - New image_cache utility module
- Real-time capability updates
  - Automatic UI refresh when tools or resources change
  - State synchronization with server changes
  - Enhanced server monitoring
- Improved result preview system
  - Better visualization of tool and resource responses
  - Added link highlighting support
  - Enhanced text formatting

### Changed

- Enhanced tool and resource response handling
  - More structured response format
  - Better support for different content types
  - Improved error reporting
- Updated integration dependencies
  - CodeCompanion updated to support new response format
  - Avante integration adapted for new capabilities
- Required mcp-hub version updated to 1.6.0

## [2.2.0] - 2025-03-08

### Added

- Avante Integration extension
  - Automatic update of [mode].avanterules files with jinja block support
  - Smart file handling with content preservation
  - Custom project root support
  - Optional jinja block usage

### Documentation

- Added detailed Avante integration guide
- Added important notes about Avante's rules file loading behavior
- Added warning about tool conflicts
- Updated example configurations with jinja blocks

## [2.1.2] - 2025-03-07

### Fixed

- Fixed redundant errors.setup in base view implementation

## [2.1.1] - 2025-03-06

### Fixed

- Fixed CodeCompanion extension's tool_schema.output.rejected handler

## [2.1.0] - 2025-03-06

### Added

- Enhanced logs view with tabbed interface for better organization
- Token count display in MCP Servers header with calculation utilities
- Improved error messaging and display system

### Changed

- Fixed JSON formatting while saving to config files
- Improved server status handling and error display
- Enhanced UI components and visual feedback
- Updated required mcp-hub version to 1.5.0

## [2.0.0] - 2025-03-05

### Added

- Persistent server and tool toggling state in config file
- Parallel startup of MCP servers for improved performance
- Enhanced Hub view with integrated server management capabilities
  - Start/stop servers directly from Hub view
  - Enable/disable individual tools per server
  - Server state persists across restarts
- Improved UI rendering with better layout and visual feedback
- Validation support for server configuration and tool states

### Changed

- Consolidated Servers view functionality into Hub view
- Improved startup performance through parallel server initialization
- Enhanced UI responsiveness and visual feedback
- Updated internal architecture for better state management
- More intuitive server and tool management interface

### Removed

- Standalone Servers view (functionality moved to Hub view)

## [1.3.0] - 2025-03-02

### Added

- New UI system with comprehensive views
  - Main view for server status
  - Servers view for tools and resources
  - Config view for settings
  - Logs view for output
  - Help view with quick start guide
- Interactive tool and resource execution interface
  - Parameter validation and type conversion
  - Real-time response display
  - Cursor tracking and highlighting
- CodeCompanion extension support
  - Integration with chat interface
  - Tool and resource access
- Enhanced state management
  - Server output handling
  - Error display with padding
  - Cursor position persistence
- Server utilities
  - Uptime formatting
  - Shutdown delay handling
  - Configuration validation

### Changed

- Improved parameter handling with ordered retrieval
- Enhanced text rendering with pill function
- Better error display with padding adjustments
- Refined UI layout and keymap management
- Updated server output management
- Enhanced documentation with quick start guide
- Upgraded version compatibility with mcp-hub 1.3.0

### Refactored

- Server uptime formatting moved to utils
- Tool execution mode improvements
- Error handling and server output management
- Configuration validation system
- UI rendering system

## [1.2.0] - 2024-02-22

### Added

- Default timeouts for operations (1s for health checks, 30s for tool/resource access)
- API tests for hub instance with examples
- Enhanced error formatting in handlers for better readability

### Changed

- Updated error handling to use simpler string format
- Added support for both sync/async API patterns across all operations
- Improved response processing and error propagation

## [1.1.0] - 2024-02-21

### Added

- Version management utilities with semantic versioning support
- Enhanced error handling with structured error objects
- Improved logging capabilities with file output support
- Callback-based initialization with on_ready and on_error hooks
- Server validation improvements with config file syntax checking
- Streamlined API error handling and response processing
- Structured logging with different log levels and output options
- Better process output handling with JSON parsing

### Changed

- Simplified initialization process by removing separate start_hub call
- Updated installation to use specific mcp-hub version
- Improved error reporting with detailed context

## [1.0.0] - 2024-02-20

### Added

- Initial release of MCPHub.nvim
- Single-command interface (:MCPHub)
- Automatic server lifecycle management
- Async operations support
- Clean client registration/cleanup
- Smart process handling
- Configurable logging
- Full API support for MCP Hub interaction
- Comprehensive error handling
- Detailed documentation and examples
- Integration with lazy.nvim package manager


