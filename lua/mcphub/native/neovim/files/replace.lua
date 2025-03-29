local Path = require("plenary.path")

-- Queue to handle multiple replace requests
local replace_queue = {}
local is_processing = false

-- Function to process the next item in queue
local function process_next_replace()
    if #replace_queue == 0 then
        is_processing = false
        return
    end

    is_processing = true
    local next_replace = table.remove(replace_queue, 1)
    next_replace.handler(next_replace.req, next_replace.res)
end

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
    -- Split content into lines for processing
    local lines = vim.split(diff_content, "\n", { plain = true })
    local result = original_content

    local in_search = false
    local in_replace = false
    local current_search = {}
    local current_replace = {}
    local blocks = {}

    -- First pass: collect all blocks
    for _, line in ipairs(lines) do
        if line == "<<<<<<< SEARCH" then
            in_search = true
            current_search = {}
        elseif line == "=======" and in_search then
            in_search = false
            in_replace = true
            current_replace = {}
        elseif line == ">>>>>>> REPLACE" and in_replace then
            in_replace = false
            table.insert(blocks, {
                search = table.concat(current_search, "\n"),
                replace = table.concat(current_replace, "\n"),
            })
        elseif in_search then
            table.insert(current_search, line)
        elseif in_replace then
            table.insert(current_replace, line)
        end
    end

    -- Validate blocks
    if #blocks == 0 then
        return "Error: No valid diff blocks found"
    end

    -- Second pass: apply blocks in order
    for _, block in ipairs(blocks) do
        local search_content = block.search
        local replace_content = block.replace

        -- Handle empty search (full file replacement)
        if search_content == "" then
            return original_content == "" and replace_content or replace_content
        end

        -- Find exact match
        local match_start = result:find(search_content, 1, true)
        if not match_start then
            -- Try line-by-line trimmed match
            local found = false
            local original_lines = vim.split(result, "\n", { plain = true })
            local search_lines = vim.split(search_content, "\n", { plain = true })

            -- Try every possible starting position
            for i = 1, #original_lines do
                if i + #search_lines - 1 > #original_lines then
                    break -- Not enough lines left to match
                end

                -- Check if all lines in this block match
                local all_match = true
                for j = 1, #search_lines do
                    local orig = vim.trim(original_lines[i + j - 1])
                    local search = vim.trim(search_lines[j])
                    if orig ~= search then
                        all_match = false
                        break
                    end
                end

                if all_match then
                    -- Calculate exact byte position
                    match_start = 0
                    for k = 1, i - 1 do
                        match_start = match_start + #original_lines[k] + 1
                    end
                    match_start = match_start + 1
                    found = true
                    break
                end
            end

            if not found then
                return string.format("Error: Could not find match for:\n%s", search_content)
            end
        end

        -- Calculate end position and handle replacement
        local match_end = match_start + #search_content - 1
        -- Ensure the newlines are preserved in replacement
        local pre = result:sub(1, match_start - 1)
        local post = result:sub(match_end + 1)

        -- If replacement doesn't end with newline but original did, preserve it
        local preserve_newline = search_content:match("\n$") and not replace_content:match("\n$")
        result = pre .. replace_content .. (preserve_newline and "\n" or "") .. post
    end

    return result
end
-- Core replace file logic
local function handle_replace_file(req, res)
    if not req.params.path or not req.params.diff then
        return res:error("Missing required parameters: path and diff")
    end

    local p = Path:new(req.params.path)
    local path = p:absolute()

    -- Validate file existence
    if not p:exists() then
        return res:error("File not found: " .. path)
    end

    -- Read original content
    local original_content = p:read()
    if not original_content then
        return res:error("Failed to read file: " .. path)
    end

    -- Parse and apply diff blocks
    local new_content = apply_diff_blocks(original_content, req.params.diff)
    if not new_content then
        return res:error("Failed to generate new content")
    end
    if type(new_content) == "string" and new_content:match("^Error:") then
        return res:error(new_content)
    end
    if type(new_content) ~= "string" or new_content == "" then
        return res:error("Invalid content generated")
    end

    -- Save current window and get target window
    local current_win = vim.api.nvim_get_current_win()
    local target_win = current_win

    if req.caller.type == "hubui" then
        req.caller.hubui:cleanup()
    end
    -- Try to use last active buffer's window if available
    if req.editor_info and req.editor_info.last_active then
        local last_active = req.editor_info.last_active
        if last_active.winnr and vim.api.nvim_win_is_valid(last_active.winnr) then
            target_win = last_active.winnr
        end
    else
        -- Get the chat window's position
        local chat_win = vim.api.nvim_get_current_win()
        local chat_col = vim.api.nvim_win_get_position(chat_win)[2]
        local total_width = vim.o.columns

        -- Determine where to place new window based on chat position
        if chat_col > total_width / 2 then
            vim.cmd("topleft vnew") -- New window on the left
        else
            vim.cmd("botright vnew") -- New window on the right
        end

        target_win = vim.api.nvim_get_current_win()
    end

    vim.api.nvim_set_current_win(target_win)
    vim.cmd("edit " .. path)
    local bufnr = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_option(bufnr, "buflisted", true)

    -- Set content and mark as modified
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.split(new_content, "\n"))
    vim.bo[bufnr].modified = true
    -- Create split for diff view
    if vim.api.nvim_win_get_width(target_win) < 70 then
        vim.cmd("split")
    else
        vim.cmd("vsplit")
    end

    -- Create diff buffer with original content
    local diff_bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_win_set_buf(vim.api.nvim_get_current_win(), diff_bufnr)
    vim.api.nvim_buf_set_lines(diff_bufnr, 0, -1, false, vim.split(original_content, "\n"))
    vim.bo[diff_bufnr].buftype = "nofile"
    vim.bo[diff_bufnr].bufhidden = "wipe"
    vim.cmd("diffthis")
    vim.api.nvim_set_current_win(target_win)
    vim.cmd("diffthis")

    -- Set up autocommands
    local augroup = vim.api.nvim_create_augroup("McpHubDiffCleanup_" .. bufnr, { clear = true })
    local augroup_cleared = false
    local file_accepted = false
    local response_sent = false
    local changes_diff = nil

    local function cleanup_diff()
        vim.cmd("diffoff!")
        if vim.api.nvim_buf_is_valid(diff_bufnr) then
            vim.api.nvim_buf_delete(diff_bufnr, { force = true })
        end
        if vim.api.nvim_buf_is_valid(bufnr) then
            vim.keymap.del("n", "ga", { buffer = bufnr })
            vim.keymap.del("n", "gr", { buffer = bufnr })
        end
        if not augroup_cleared then
            pcall(vim.api.nvim_del_augroup_by_id, augroup)
            augroup_cleared = true
        end
        vim.schedule(function()
            process_next_replace()
        end)
    end

    local function capture_changes()
        local current_content = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
        changes_diff = vim.diff(new_content, current_content, {
            result_type = "unified",
        })
    end

    local function send_response(accepted)
        if not response_sent then
            response_sent = true
            if accepted then
                local msg = string.format(
                    "Successfully replaced content in: %s\nApplied %d change blocks",
                    path,
                    count_diff_blocks(req.params.diff)
                )
                if changes_diff and changes_diff ~= "" then
                    msg = msg .. "\n\nUser made additional changes:\n```diff\n" .. changes_diff .. "\n```"
                end
                res:text(msg):send()
            else
                res:text("User rejected the changes: " .. path):send()
            end
        end
    end

    local function handle_post_write()
        if response_sent then
            return
        end
        capture_changes()
        file_accepted = true
        cleanup_diff()
        send_response(true)
    end

    local function handle_reject()
        if response_sent then
            return
        end
        file_accepted = false
        cleanup_diff()
        send_response(false)
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.split(original_content, "\n"))
        vim.cmd("write")
    end

    -- Set up key mappings
    vim.keymap.set("n", "ga", function()
        vim.cmd("write")
        handle_post_write()
    end, { buffer = bufnr, desc = "Accept changes" })

    vim.keymap.set("n", "gr", function()
        handle_reject()
    end, { buffer = bufnr, desc = "Reject changes" })

    -- Set up autocommands
    vim.api.nvim_create_autocmd("BufWritePost", {
        group = augroup,
        buffer = bufnr,
        callback = handle_post_write,
    })

    vim.api.nvim_create_autocmd("BufUnload", {
        group = augroup,
        buffer = bufnr,
        callback = function()
            if not file_accepted then
                handle_reject()
            end
        end,
    })
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
     - CRUCIAL: Empty SEARCH block is something with empty lines(\n) or whitespaces, ONLY use empty SEARCH block if you are sure the file is empty or you want to replace the entire file content
     - To replace an empty line, the SEARCH block must contain a line with some content that is somewhere above or below the empty line to avoid replacing the entire file content
       <<<<<<< SEARCH
       line with some content
       
       =======
       line with some content
       [new content]
       >>>>>>> REPLACE
     - Empty SEARCH block in empty file: Creates new file with REPLACE content
     - Empty SEARCH block in non-empty file: Replaces entire file content
     - To move code: Use two blocks (delete from source + insert at destination)
     - To delete code: Use empty REPLACE section]],
    inputSchema = {
        type = "object",
        properties = {
            path = {
                type = "string",
                description = "Path to the file to modify",
            },
            diff = {
                type = "string",
                description = "One or more SEARCH/REPLACE blocks defining the changes",
            },
        },
        required = { "path", "diff" },
    },
    handler = function(req, res)
        table.insert(replace_queue, {
            req = req,
            res = res,
            handler = handle_replace_file,
        })

        if not is_processing then
            process_next_replace()
        end
    end,
}
