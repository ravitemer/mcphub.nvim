local Path = require("plenary.path")

-- Helper function to count diff blocks
local function count_diff_blocks(diff_content)
    local count = 0
    for _ in diff_content:gmatch("<<<<<<< SEARCH") do
        count = count + 1
    end
    return count
end

-- Helper function to apply diff blocks
local function apply_diff_blocks(original_content, diff_content)
    local result = original_content
    local last_processed_index = 1

    -- Split diff into blocks
    for search_block in diff_content:gmatch("<<<<<<< SEARCH\n(.-)\n=======\n(.-)\n>>>>>>> REPLACE") do
        local search_content, replace_content = search_block:match("(..-)\n=======\n(..-)\n>>>>>>> REPLACE")

        if not search_content then
            -- Handle empty search (full file replacement)
            if original_content == "" then
                return replace_content
            else
                result = replace_content
                break
            end
        end

        -- Find exact match first
        local match_start = result:find(search_content, last_processed_index, true)

        if not match_start then
            -- Try line-trimmed fallback
            local found = false
            local original_lines = vim.split(result, "\n", { plain = true })
            local search_lines = vim.split(search_content, "\n", { plain = true })

            for i = last_processed_index, #original_lines - #search_lines + 1 do
                local matches = true
                for j = 1, #search_lines do
                    if vim.trim(original_lines[i + j - 1]) ~= vim.trim(search_lines[j]) then
                        matches = false
                        break
                    end
                end

                if matches then
                    -- Calculate match position
                    match_start = 1
                    for k = 1, i - 1 do
                        match_start = match_start + #original_lines[k] + 1
                    end
                    found = true
                    break
                end
            end

            if not found then
                return string.format("Error: Could not find match for:\n%s", search_content)
            end
        end

        -- Calculate match end position
        local match_end = match_start + #search_content

        -- Replace matched content
        result = result:sub(1, match_start - 1) .. replace_content .. result:sub(match_end)
        last_processed_index = match_start + #replace_content
    end

    return result
end

return {
    name = "replace_in_file",
    description = [[Replace sections of content in an existing file using SEARCH/REPLACE blocks.

DESCRIPTION:
  This tool makes targeted changes to specific parts of a file using a special block format
  that precisely defines what content to find and what to replace it with.

FORMAT:
  Each change must be specified using this exact block structure:

  <<<<<<< SEARCH
  [exact content to find]
  =======
  [new content to replace with]
  >>>>>>> REPLACE

CRITICAL RULES:
  1. SEARCH content must match EXACTLY:
     - Match character-for-character including whitespace and indentation
     - Include all comments, line endings, etc.
     - Partial line matches are not supported

  2. Block Ordering:
     - Multiple blocks are processed in order, top to bottom
     - List blocks in the order they appear in the file
     - Each block will only replace its first match

  3. Best Practices:
     - Include just enough lines to uniquely identify the section to change
     - Break large changes into multiple smaller blocks
     - Don't include long runs of unchanged lines
     - Always use complete lines, never partial lines

  4. Special Cases:
     - Empty SEARCH block in empty file: Creates new file with REPLACE content
     - Empty SEARCH block in non-empty file: Replaces entire file content
     - To move code: Use two blocks (delete from source + insert at destination)
     - To delete code: Use empty REPLACE section]],
    inputSchema = {
        type = "object",
        properties = {
            path = {
                type = "string",
                description = "Path to the file to modify (relative to current working directory)",
            },
            diff = {
                type = "string",
                description = "One or more SEARCH/REPLACE blocks defining the changes",
            },
        },
        required = { "path", "diff" },
    },
    handler = function(req, res)
        local params = req.params
        local p = Path:new(params.path)

        -- Validate file existence
        if not p:exists() then
            return res:error("File not found: " .. params.path)
        end

        -- Read original content
        local original_content = p:read()
        if not original_content then
            return res:error("Failed to read file: " .. params.path)
        end

        -- Parse and apply diff blocks
        local new_content = apply_diff_blocks(original_content, params.diff)
        if type(new_content) == "string" and new_content:match("^Error:") then
            return res:error(new_content)
        end

        -- Write new content with backup
        local ok, err = pcall(function()
            -- Create backup
            local backup_content = original_content

            -- Write new content
            p:write(new_content, "w")

            -- Verify write
            local verify = p:read()
            if verify ~= new_content then
                -- Restore from backup if verification fails
                p:write(backup_content, "w")
                error("Failed to verify written content")
            end
        end)

        if not ok then
            return res:error("Failed to write changes: " .. tostring(err))
        end

        -- Report success with change summary
        local changes = count_diff_blocks(params.diff)
        return res:text(string.format("Successfully edited file: %s\nApplied %d change blocks", params.path, changes))
            :send()
    end
}