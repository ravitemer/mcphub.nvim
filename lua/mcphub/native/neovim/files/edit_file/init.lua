local State = require("mcphub.state")
---New modular editor tool using EditSession
---@type MCPTool
local edit_file_tool = {
    name = "edit_file",
    description = [[Replace multiple sections in a file using SEARCH/REPLACE blocks that define exact changes to specific parts of the file. This tool starts an interactive edit session in Neovim. The user might accept some changes, reject some or add new text during the edit session. Once the edit session completes the result will include useful information like diff and feedback which you MUST take into account for SUBSEQUENT conversation: 
1. A diff comparing the file before and after the edit session. The diff might be a result of a combination of:
   - Changes from successfully applied SEARCH/REPLACE blocks
   - Changes made by the USER during the edit session
   - Changes made by the FORMATTERS or LINTERS that were run before the file is saved
2. Feedback from the edit session, which might include:
   - Any issues while PARSING the SEARCH/REPLACE blocks and how they were resolved
   - Any issues encountered while FINDING the SEARCH content in the file like:
     - SEARCH content not found (will provide the best match found for the SEARCH content) or
     - SEARCH content found but with fuzzy matching (will provide a confidence score and the diff between SEARCH content and the fuzzy match)
   - Any additional user feedback provided during the edit session
3. Diagnostics in the file after the edit session is completed

IMPORTANT: The diff will show you what all changes were made, and the feedback will provide additional context on how the SEARCH/REPLACE blocks were applied to avoid any issues in subsequent calls. You MUST give EXTREME care to the result of this tool or else you will be fired!!! 
IMPORTANT: The tool is NEVER wrong. Once edits are shown in the buffer, user might make any additional changes like adding some new comment or editing the replace text you sent. This MUST be considered as intentional and is not a bug in the tool. Hence, careful observation of the diff and feedback is CRITICAL to avoid any issues in subsequent calls.
]],
    needs_confirmation_window = false, -- will show interactive diff, avoid double confirmations
    inputSchema = {
        type = "object",
        properties = {
            path = {
                type = "string",
                description = "The path to the file to modify",
            },
            diff = {
                type = "string",
                description = [[One or more SEARCH/REPLACE blocks following this exact format:

<<<<<<< SEARCH
[exact content to find]
=======
[new content to replace with]
>>>>>>> REPLACE

CRITICAL: 
- When there are two or more related changes needed in a file, always use multiple SEARCH/REPLACE blocks in the diff from the start of the file to the end. Each block should contain the exact content to find and the new content to replace it with. Failing to do so or using multiple calls with single SEARCH/REPLACE block will result in you being fired!!!
- The markers `<<<<<<< SEARCH`, `=======`, and `>>>>>>> REPLACE` MUST be exact with no other characters on the line.


Examples:

1. Multiple changes in one call from top to bottom: 
<<<<<<< SEARCH
import os
=======
import os
import json
>>>>>>> REPLACE

<<<<<<< SEARCH
def process_data():
    # old implementation
    pass
=======
def process_data():
    # new implementation
    with open('data.json') as f:
        return json.load(f)
>>>>>>> REPLACE

<<<<<<< SEARCH
if __name__ == '__main__':
    print("Starting")
=======
if __name__ == '__main__':
    print("Starting with new config")
    process_data()
>>>>>>> REPLACE

2. Deletion example:
<<<<<<< SEARCH
def unused_function():
    return "delete me"

=======
>>>>>>> REPLACE

3. Adding new content at end: 
CAUTION: Whitespaces or newlines without any other content in the SEARCH section will replace the entire file!!! This will lead to loss of all content in the file. Searching for empty lines or whitespace in order to replace something is not allowed. Only use empty SEARCH blocks if you want to replace the ENTIRE file content.
<<<<<<< SEARCH
    return result


=======
    return result

def new_helper_function():
    return "helper"
>>>>>>> REPLACE

4. Replacing same content multiple times:
<<<<<<< SEARCH
count = 0
=======
counter = 0
>>>>>>> REPLACE

<<<<<<< SEARCH
print("Count is", count)
=======
print("Counter is", counter)
>>>>>>> REPLACE

<<<<<<< SEARCH
print("Count is", count)
=======
print("Counter is", counter)
>>>>>>> REPLACE

CRITICAL RULE:
When the SEARCH or REPLACE content includes lines that start with markers like `<<<<<<<`, `=======`, or `>>>>>>>`, you MUST escape them by adding a backslash before each marker so that tool doesn't parse them as actual markers. For example, to search for content that has `<<<<<<< SEARCH`, use `\<<<<<<< SEARCH` in the SEARCH block.

5. Escaping markers in SEARCH/REPLACE content:
<<<<<<< SEARCH
Tutorial:
A marker has < or > or = in it. E.g
\<<<<<<< SEARCH
=======
Tutorial:
A marker will have < or > or = in it. e.g
\=======
>>>>>>> REPLACE


CRITICAL rules:
1. SEARCH content must match the file section EXACTLY:
   - Character-for-character including whitespace, indentation, line endings
   - Include all comments, docstrings, etc.
2. SEARCH/REPLACE blocks will ONLY replace the first match occurrence
   - To replace same content multiple times: Use multiple SEARCH/REPLACE blocks for each occurrence 
   - When using multiple SEARCH/REPLACE blocks, list them in the order they appear in the file
3. Keep SEARCH/REPLACE blocks concise:
   - Include just the changing lines, and a few surrounding lines if needed for uniqueness
   - Break large blocks into smaller blocks that each change a small portion. Searching for entire functions or large sections when only a few lines need changing will get you fired!!!
   - Each line must be complete. Never truncate lines mid-way through as this can cause matching failures
4. Special operations:
   - To move code: Use two blocks (one to delete from original + one to insert at new location)
   - To delete code: Use empty REPLACE section

IMPORTANT: Batch multiple related changes for a file into a single call to minimize user interactions.
]],
            },
        },
        required = { "path", "diff" },
    },
    handler = function(req, res)
        local params = req.params
        if not params.path or vim.trim(params.path) == "" then
            return res:error("Missing required parameter: path")
        end
        if not params.diff or vim.trim(params.diff) == "" then
            return res:error("Missing required parameter: diff")
        end
        -- Handle hub UI cleanup
        if req.caller and req.caller.type == "hubui" then
            req.caller.hubui:cleanup()
        end
        local EditSession = require("mcphub.native.neovim.files.edit_file.edit_session")
        local session = EditSession.new(params.path, params.diff, State.config.inbuilt_tools.edit_file)
        session:start({
            interactive = req.caller.auto_approve ~= true,
            on_success = function(summary)
                res:text(summary):send()
            end,
            on_error = function(error_report)
                res:error(error_report)
            end,
        })
    end,
}

return edit_file_tool
