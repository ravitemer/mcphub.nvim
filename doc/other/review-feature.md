# Tool Result Review Feature

The "Yes & Review" feature provides an additional layer of control over MCP tool execution, allowing you to review tool results before they're sent to the LLM. This is particularly useful when working with tools that might return sensitive information.

## Overview

When executing MCP tools, you now have four options in the confirmation dialog:

1. **Yes** - Execute the tool and send results directly to the LLM
2. **Yes & Review** - Execute the tool, then show a review window before sending to LLM
3. **No** - Don't execute the tool
4. **Cancel** - Cancel the operation

## Use Cases

### Prevent Data Leakage

When using MCP servers that access sensitive data (e.g., JIRA, Confluence, internal databases), you may want to review the results before they're shared with the LLM:

```
LLM: "Let me check your recent JIRA issues"
You: Press 'r' for "Yes & Review"
Tool executes and fetches JIRA data
Review window appears with the results
You can inspect for sensitive information
Approve or reject before sending to LLM
```

### Quality Control

Review tool outputs to ensure they're correct and relevant before the LLM processes them, especially for:
- Complex queries with large result sets
- File operations that might have grabbed wrong content
- API calls that might have returned unexpected data

### Learning and Debugging

See exactly what data tools are returning to help:
- Understand how MCP servers work
- Debug issues with tool calls
- Learn what information is being shared with the LLM

## How It Works

### Confirmation Flow

When a tool requires confirmation, you'll see:

```
┌─────────────────────────────────────────┐
│       MCPHUB Confirmation               │
├─────────────────────────────────────────┤
│ Server: github                          │
│ Tool: search_issues                     │
│ Arguments: { repo: "user/project" }     │
│                                         │
│  [Yes]  [Yes & Review]  [No]  [Cancel]  │
└─────────────────────────────────────────┘
```

**Keyboard shortcuts:**
- `y`/`Y` - Yes (execute and auto-send)
- `r`/`R` - Yes & Review (execute and show review window)
- `n`/`N` - No (don't execute)
- `c`/`C` or `<Esc>` or `q` - Cancel
- `<Tab>` - Navigate between options
- `<CR>` - Execute highlighted option

### Review Window

If you select "Yes & Review", after the tool executes, you'll see a review window:

```
┌────────────────────────────────────────────┐
│         Tool Result Review                 │
├────────────────────────────────────────────┤
│ Server: jira                               │
│ Tool: search_issues                        │
│                                            │
│ ━━━ Result ━━━                             │
│                                            │
│ [Scrollable content showing tool results] │
│ • Text results are displayed              │
│ • Images show count indicator             │
│ • Errors are highlighted                  │
│                                            │
│        [Approve]    [Reject]               │
└────────────────────────────────────────────┘
```

**Keyboard shortcuts:**
- `y`/`Y` or `a`/`A` - Approve (send result to LLM)
- `n`/`N` or `r`/`R` - Reject (don't send to LLM)
- `<Esc>` or `q` - Reject (same as above)
- `<Tab>` - Navigate between Approve/Reject
- `<CR>` - Execute highlighted option

**Scrolling:**
- `j`/`k` - Scroll line by line
- `<C-d>`/`<C-u>` - Scroll half page
- `gg`/`G` - Jump to top/bottom

### What Happens on Rejection

When you reject a tool result, the LLM receives a neutral message instead:

```
"Tool result was rejected by the user during review."
```

This allows the LLM to:
- Ask you what information you need instead
- Try a different approach
- Request clarification on what to do next

The actual tool result is never sent to the LLM, preventing any sensitive data leakage.

## Configuration

### Using auto_approve Function

You can use the `auto_approve` function to automatically trigger review for specific servers or tools:

```lua
require("mcphub").setup({
    auto_approve = function(params)
        -- Auto-approve filesystem operations (no review needed)
        if params.server_name == "neovim" then
            return true
        end
        
        -- Execute JIRA/Confluence tools but always review results
        if params.server_name == "jira" or params.server_name == "confluence" then
            return { approve = true, review = true }
        end
        
        -- Execute but review for any tool accessing external APIs
        if params.tool_name and params.tool_name:match("^fetch") then
            return { approve = true, review = true }
        end
        
        -- Everything else requires manual confirmation
        return false
    end
})
```

**Return values:**
- `true` - Execute immediately, no review
- `false` - Show confirmation dialog (user can choose review)
- `{ approve: true, review: true }` - Execute and force review
- `{ approve: false, review: false }` - Don't execute (same as false)
- `string` - Deny with error message

### Important Notes

1. **Auto-approved tools skip review**: If a tool is auto-approved (via `auto_approve = true`, `servers.json` `autoApprove`, or function returning `true`), it will execute and send results directly to the LLM without showing any dialogs.

2. **Review is always available**: The "Yes & Review" option appears in all confirmation dialogs. Users can always choose to review results even if not configured.

3. **Review happens after execution**: The tool runs first, then results are shown for review. This means side effects (like creating a file) have already occurred, but you control what data reaches the LLM.

## Examples

### Example 1: Reviewing JIRA Data

```lua
-- Configuration
require("mcphub").setup({
    auto_approve = function(params)
        if params.server_name == "jira" then
            return { approve = true, review = true }
        end
        return false
    end
})
```

When CodeCompanion calls a JIRA tool:
1. Tool executes automatically (no confirmation dialog)
2. Review window appears with JIRA data
3. You inspect the issues, descriptions, etc.
4. Approve if data is safe, reject if it contains sensitive info
5. LLM only sees approved data

### Example 2: Manual Review for Database Queries

```lua
-- Configuration
require("mcphub").setup({
    auto_approve = function(params)
        -- Always require confirmation for database operations
        if params.server_name == "postgres" or params.server_name == "mongodb" then
            return false -- Show confirmation dialog
        end
        return false
    end
})
```

When CodeCompanion wants to query a database:
1. Confirmation dialog appears
2. You press `r` for "Yes & Review"
3. Query executes
4. Review window shows the query results
5. You can verify no PII or sensitive data is present
6. Approve to continue

### Example 3: Selective Review Based on Arguments

```lua
require("mcphub").setup({
    auto_approve = function(params)
        -- Auto-approve reading from public directories
        if params.tool_name == "read_file" then
            local path = params.arguments.path or ""
            if path:match("/public/") or path:match("/docs/") then
                return true -- No review needed
            end
            -- Force review for other paths
            return { approve = true, review = true }
        end
        
        return false
    end
})
```

## Security Considerations

### Why This Feature Exists

MCP tools can access and return sensitive information:
- Personal data from issue trackers
- Confidential documents
- API keys or credentials in config files
- Internal company information
- Private code or data

Once this information reaches the LLM, you lose control over it. The review feature ensures you maintain control over what data is shared.

### Best Practices

1. **Review by default for sensitive sources**: Configure auto-review for any MCP server that accesses:
   - Internal company tools (JIRA, Confluence, etc.)
   - Databases with customer data
   - Private repositories or codebases
   - Any service with PII (Personally Identifiable Information)

2. **Auto-approve safe operations**: It's safe to auto-approve (without review):
   - Local file operations in public directories
   - Read-only operations on public data
   - Tools you've thoroughly vetted

3. **Use rejection strategically**: When you reject results:
   - The tool has already executed (side effects occurred)
   - Only the data transmission to LLM is prevented
   - Use this for data leakage prevention, not execution prevention

4. **Combine with other security measures**:
   - Use MCP server permissions and scopes
   - Configure tools with least-privilege access
   - Review `servers.json` configurations regularly

## Troubleshooting

### Review window closes immediately

Make sure you're not in insert mode. The review window operates in normal mode with specific key bindings.

### Results are truncated

Very large results (>10,000 lines) are automatically truncated to prevent performance issues. The truncation message will indicate how many lines are shown vs. total.

### Tool executes even when rejected

This is expected behavior. The review happens *after* execution. If you need to prevent execution entirely, select "No" or "Cancel" in the confirmation dialog instead of "Yes & Review".

### Can't see images in review window

Images are shown as a count indicator (e.g., "📷 2 images included") in the review window. The actual images are still included in the result when approved, and CodeCompanion will display them in the chat buffer.

## Related Documentation

- [CodeCompanion Integration](/extensions/codecompanion) - Full CodeCompanion extension documentation
- [Configuration](/configuration) - Main configuration options including `auto_approve`
- [Architecture: Review Flow](/other/architecture/review-flow) - Technical implementation details
