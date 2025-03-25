# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
