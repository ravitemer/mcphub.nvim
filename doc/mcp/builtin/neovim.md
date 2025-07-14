# Neovim Server

The Neovim server (`neovim`) is the primary inbuilt native server that provides comprehensive file operations, terminal access, and deep Neovim integration. It offers essential tools for LLMs to interact with your development environment.

## Tools

### `edit_file` 
Advanced interactive file editing using SEARCH/REPLACE blocks. This is the most sophisticated builtin tool for making precise file modifications.

**Parameters:**
- `path` (string, required): Path to the file to modify
- `diff` (string, required): One or more SEARCH/REPLACE blocks

**SEARCH/REPLACE Format:**
```
<<<<<<< SEARCH
exact content to find
=======
new content to replace with
>>>>>>> REPLACE
```

**Key Features:**
- Interactive diff preview with navigation
- Fuzzy matching when exact content isn't found
- Multiple blocks in a single operation
- Comprehensive feedback including confidence scores
- Smart error handling and suggestions

**Configuration:**
```lua
require("mcphub").setup({
    builtin_tools = {
        edit_file = {
            parser = {
                track_issues = true,              -- Track parsing issues for LLM feedback
                extract_inline_content = true,   -- Handle content on marker lines
            },
            locator = {
                fuzzy_threshold = 0.8,           -- Minimum similarity for fuzzy matches (0.0-1.0)
                enable_fuzzy_matching = true,    -- Allow fuzzy matching when exact fails
            },
            ui = {
                go_to_origin_on_complete = true, -- Jump back to original file on completion
                keybindings = {
                    accept = ".",                 -- Accept current change
                    reject = ",",                 -- Reject current change
                    next = "n",                   -- Next diff
                    prev = "p",                   -- Previous diff
                    accept_all = "ga",           -- Accept all remaining changes
                    reject_all = "gr",           -- Reject all remaining changes
                },
            },
            feedback = {
                include_parser_feedback = true,   -- Include parsing feedback for LLM
                include_locator_feedback = true,  -- Include location feedback for LLM
                include_ui_summary = true,        -- Include UI interaction summary
                ui = {
                    include_session_summary = true,     -- Include session summary in feedback
                    include_final_diff = true,          -- Include final diff in feedback
                    send_diagnostics = true,            -- Include diagnostics after editing
                    wait_for_diagnostics = 500,         -- Wait time for diagnostics (ms)
                    diagnostic_severity = vim.diagnostic.severity.WARN, -- Min severity to include
                },
            },
        },
    },
})
```

For scenarios where interactive diff is not necessary , You can `autoApprove` the `edit_file` or `write_file` tool in the UI with `a` or by editing the `servers.json` file.

### `write_file`
Write content to a file with interactive diff preview.

**Parameters:**
- `path` (string, required): Path to the file to write
- `content` (string, required): Content to write to the file

**Features:**
- Shows interactive diff before applying changes
- Creates directories if they don't exist
- Respects `auto_approve` configuration


### `read_file`
Read contents of a file with optional line range selection.

**Parameters:**
- `path` (string, required): Path to the file to read
- `start_line` (number, optional): Start reading from this line (1-based, default: 1)
- `end_line` (number, optional): Read until this line inclusive (default: -1 for end of file)

### `read_multiple_files`
Read contents of multiple files in parallel for efficient batch operations.

**Parameters:**
- `paths` (array of strings, required): Array of file paths to read

### `move_item`
Move or rename files and directories.

**Parameters:**
- `path` (string, required): Source path
- `new_path` (string, required): Destination path

### `delete_items`
Delete multiple files or directories safely.

**Parameters:**
- `paths` (array of strings, required): Array of paths to delete


### `find_files`
Search for files using glob patterns with comprehensive filtering.

**Parameters:**
- `pattern` (string, required): Search pattern (e.g., "*.lua", "**/*.md")
- `path` (string, optional): Directory to search in (default: ".")
- `recursive` (boolean, optional): Search recursively (default: true)

### `list_directory`
List files and directories with detailed information.

**Parameters:**
- `path` (string, optional): Directory path to list (default: ".")


### `execute_command`
Execute shell commands with full output capture and error handling.

**Parameters:**
- `command` (string, required): Shell command to execute
- `cwd` (string, required): Working directory for the command

**Features:**
- Captures both stdout and stderr
- Reports exit codes
- Environment inherited from Neovim
- Async execution with progress feedback

**Example:**
```json
{
    "command": "npm test",
    "cwd": "/path/to/project"
}
```

### `execute_lua`
Execute Lua code directly in Neovim using `nvim_exec2`.

**Parameters:**
- `code` (string, required): Lua code to execute

**Features:**
- Full access to Neovim API
- Output capture and formatting
- Error handling with stack traces
- Support for complex data structures

## Resources

#### Buffer Information (`neovim://buffer`)
Comprehensive information about the currently active buffer.

**Provides:**
- Buffer metadata (name, number, line count)
- Full buffer content with line numbers
- Cursor position indicator
- Buffer marks
- Quickfix entries for the buffer

**Content Format:**
```
## Buffer Information
Name: /path/to/file.lua
Bufnr: 42
Lines: 156
Cursor: line 15

## Buffer Content
> 15 │ local function example()
  16 │     return "hello"
  17 │ end

## Marks
a: line 10, col 5: local variable = value

## Quickfix Entries
25 │ print("debug message")
   └─ Debug statement found
```

#### Environment Information (`neovim://workspace`)
Comprehensive workspace and system information for context-aware assistance.

**Provides:**
- System information (OS, hostname, memory)
- Workspace details (current directory, git status)
- Neovim buffer states (visible, loaded files)
- File structure overview
- Environment variables and shell info

**Content Format:**
```xml
<environment_details>
## System Information
OS: Linux (x86_64)
Hostname: development-machine
User: developer
Shell: /bin/zsh
Memory: 16.00 GB total, 8.45 GB free

## Workspace
Current Directory: /home/dev/project
Git Repository: Yes
Files: 127

## Workspace Files
main.lua (file, 2.45KB)
config/ (directory, 0.00KB)

## Neovim Visible Files
src/main.lua (active)
test/spec.lua
README.md

## Neovim Loaded Files
.gitignore
package.json
</environment_details>
```

#### LSP Diagnostics

#### Current File Diagnostics (`neovim://diagnostics/buffer`)
LSP diagnostics for the currently active buffer.

**Provides:**
- Error, warning, info, and hint diagnostics
- Line and column positions
- Source information (ESLint, typescript, etc.)
- Diagnostic codes and messages

#### Workspace Diagnostics (`neovim://diagnostics/workspace`)
LSP diagnostics across all open buffers.

**Provides:**
- Diagnostics grouped by file
- Complete workspace health overview
- Cross-file issue tracking

