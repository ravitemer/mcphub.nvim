local keymap_utils = require("mcphub.native.neovim.utils.keymap")
local text = require("mcphub.utils.text")

---@class EditUI
---@field config UIConfig Configuration options
---@field state UIState Current UI state
---@field highlights table Highlight management
local EditUI = {}
EditUI.__index = EditUI

-- UI State tracking
---@class UIState
---@field origin_winnr integer Window number of the start
---@field bufnr integer Buffer number being edited
---@field file_path string Path to the file
---@field located_blocks LocatedBlock[] Blocks to process
---@field original_content string Original file content
---@field callbacks table Success/cancel callbacks
---@field augroup integer Autocommand group ID
---@field is_replacing_entire_file boolean Whether the entire file is being replaced
---@field hunk_extmarks table<string, integer[]> A map of block_id to a list of extmark IDs for its hunks
---@field has_completed boolean Whether the session has been completed
---@field hunk_blocks DiffHunk[] Generated hunk blocks for granular navigation
---@field completed_hunks table<string, string> Map of hunk_id to completion status
---@field current_hunk_index integer Currently active hunk (1-based)
---@field original_keymaps table<string, table|nil> Stored original keymaps before session

-- Default UI configuration
local DEFAULT_CONFIG = {
    auto_navigate = true,
    go_to_origin_on_complete = true,
    send_diagnostics = true,
    wait_for_diagnostics = 1000,
    diagnostic_severity = vim.diagnostic.severity.WARN, -- Only show warnings and above by default
    keybindings = {
        accept = ".", -- Accept current change
        reject = ",", -- Reject current change
        next = "n", -- Next diff
        prev = "p", -- Previous diff
        accept_all = "ga", -- Accept all remaining changes
        reject_all = "gr", -- Reject all remaining changes
    },
}

-- Create new EditUI instance
---@param config UIConfig? Optional configuration
---@return EditUI
function EditUI.new(config)
    local self = setmetatable({}, EditUI)
    self.config = vim.tbl_deep_extend("force", DEFAULT_CONFIG, config or {})
    self.state = nil
    self.highlights = {
        namespace_diff = vim.api.nvim_create_namespace("mcphub-editor-diff"),
        namespace_hints = vim.api.nvim_create_namespace("mcphub-editor-hints"),
        priority = 20000,
    }
    return self
end

-- Start interactive editing session
---@param opts table Session options
function EditUI:start_interactive_editing(opts)
    local buf_utils = require("mcphub.native.neovim.utils.buffer")
    local bufnr = buf_utils.open_file_in_editor(opts.file_path)
    if not bufnr then
        return opts.on_error("Couldn't open buffer for editing")
    end
    self.state = {
        origin_winnr = opts.origin_winnr,
        bufnr = bufnr,
        is_replacing_entire_file = opts.is_replacing_entire_file,
        file_path = opts.file_path,
        located_blocks = opts.located_blocks,
        original_content = opts.original_content,
        hunk_extmarks = {},
        current_hunk_index = 1,
        completed_hunks = {},
        callbacks = {
            on_complete = opts.on_complete,
            on_cancel = opts.on_cancel,
        },
        has_completed = false,
        augroup = vim.api.nvim_create_augroup("mcphub_editor_ui", { clear = true }),
    }

    self:_setup_autocmds()
    self:_apply_all_changes()

    -- Generate hunk blocks for granular navigation
    self:_generate_hunk_blocks()

    -- Early completion if no actual changes were found
    if not self.state.hunk_blocks or #self.state.hunk_blocks == 0 then
        return self:_complete_session()
    end

    if opts.interactive == false then
        return self:_handle_save()
    end

    self:_highlight_all_blocks()

    self:_setup_keybindings()

    if self.config.auto_navigate then
        self:_navigate_to_hunk(1)
    end

    self:_update_hints()
end
-- Apply all changes from located blocks to the buffer
function EditUI:_apply_all_changes()
    local base_line_offset = 0

    local sorted_blocks = self.state.located_blocks
    table.sort(sorted_blocks, function(a, b)
        return a.location_result.start_line < b.location_result.start_line
    end)

    -- Apply each block's changes
    for _, block in ipairs(sorted_blocks) do
        local start_line = block.location_result.start_line + base_line_offset
        local end_line = block.location_result.end_line + base_line_offset

        -- Apply the replacement
        vim.api.nvim_buf_set_lines(
            self.state.bufnr,
            start_line - 1, -- Convert to 0-based
            end_line,
            false,
            block.replace_lines
        )

        -- Update the block's position after changes
        block.applied_start_line = start_line
        block.applied_end_line = start_line + #block.replace_lines - 1

        -- Calculate offset for next blocks
        local line_diff = #block.replace_lines - (end_line - start_line + 1)
        base_line_offset = base_line_offset + line_diff
    end
end

---Generate hunk blocks from located blocks for granular navigation
---@return DiffHunk[]
function EditUI:_generate_hunk_blocks()
    self.state.hunk_blocks = {}

    for _, located_block in ipairs(self.state.located_blocks) do
        -- Calculate precise diff hunks
        local precise_diff_hunks = {}
        local location_result = located_block.location_result
        if location_result.found then
            precise_diff_hunks = vim.diff(
                table.concat(location_result.found_lines, "\n"),
                table.concat(located_block.replace_lines, "\n"),
                { result_type = "indices", algorithm = "histogram", ctxlen = 3 }
            ) or {} --[[@as table<integer, integer>]]
        end
        -- Process each precise_diff_hunk
        for hunk_index, hunk in ipairs(precise_diff_hunks) do
            local old_start_idx, old_count, new_start_idx, new_count = unpack(hunk)

            -- Extract actual old/new content for this hunk
            local old_lines = {}
            for i = old_start_idx, old_start_idx + old_count - 1 do
                table.insert(old_lines, located_block.location_result.found_lines[i] or "")
            end

            local new_lines = {}
            for i = new_start_idx, new_start_idx + new_count - 1 do
                table.insert(new_lines, located_block.replace_lines[i] or "")
            end

            -- Determine hunk type
            local hunk_type = "change"
            if old_count == 0 then
                hunk_type = "addition"
            elseif new_count == 0 then
                hunk_type = "deletion"
            end

            -- Calculate absolute position in buffer
            local absolute_start = located_block.applied_start_line + new_start_idx - 1
            local absolute_end = absolute_start + new_count - 1

            -- For pure deletions, position is where content was removed
            if new_count == 0 then
                absolute_start = located_block.applied_start_line + old_start_idx - 1
                absolute_end = absolute_start -- No actual lines in buffer
            end

            ---@type DiffHunk
            local hunk_block = {
                hunk_id = string.format("%s_hunk_%d", located_block.block_id, hunk_index),
                parent_id = located_block.block_id,
                old_lines = old_lines,
                new_lines = new_lines,
                type = hunk_type,
                applied_start_line = absolute_start,
                applied_end_line = absolute_end,
                extmark_id = nil, -- Will be set during highlighting
                deletion_position = new_count == 0 and absolute_start or nil,
                confidence = located_block.location_result.confidence or 100, -- Default to 100% confidence
            }

            table.insert(self.state.hunk_blocks, hunk_block)
        end
    end
    return self.state.hunk_blocks
end

-- Highlight hunk blocks in the buffer (new hunk-based approach)
function EditUI:_highlight_all_blocks()
    vim.api.nvim_buf_clear_namespace(self.state.bufnr, self.highlights.namespace_diff, 0, -1)

    if not self.state.hunk_blocks then
        return
    end

    for _, hunk_block in ipairs(self.state.hunk_blocks) do
        self:_highlight_hunk_block(hunk_block)
    end
end

--- Highlight a single hunk block with proper boundary handling
---@param hunk_block DiffHunk Block to highlight
function EditUI:_highlight_hunk_block(hunk_block)
    -- Handle new content highlighting (changes and additions)
    if hunk_block.type == "change" or hunk_block.type == "addition" then
        hunk_block.extmark_id = vim.api.nvim_buf_set_extmark(
            self.state.bufnr,
            self.highlights.namespace_diff,
            hunk_block.applied_start_line - 1,
            0,
            {
                hl_group = text.highlights.diff_add,
                end_row = hunk_block.applied_end_line,
                hl_eol = true,
                hl_mode = "combine",
                priority = self.highlights.priority,
            }
        )
    end

    -- Handle old content as virtual lines (changes and deletions)
    if hunk_block.type == "change" or hunk_block.type == "deletion" then
        local virt_lines = {}
        local function pad_line(line)
            local max_cols = vim.o.columns
            local line_length = #line
            if line_length < max_cols then
                return line .. string.rep(" ", max_cols - line_length)
            end
        end

        -- Add deletion indicator for pure deletions
        if hunk_block.type == "deletion" then
            table.insert(virt_lines, {
                {
                    pad_line(
                        string.format(
                            "[DELETED %d line%s]",
                            #hunk_block.old_lines,
                            #hunk_block.old_lines > 1 and "s" or ""
                        )
                    ),
                    text.highlights.diff_delete,
                },
            })
        end

        -- Add old content lines
        for _, line in ipairs(hunk_block.old_lines) do
            table.insert(virt_lines, { { pad_line(line), text.highlights.diff_delete } })
        end

        -- Calculate virtual line placement with boundary handling
        local virt_line_row, virt_lines_above = self:_calculate_virtual_line_placement(hunk_block)

        local extmark_opts = {
            virt_lines = virt_lines,
            virt_lines_above = virt_lines_above,
            priority = self.highlights.priority,
        }

        -- For pure deletions, store the extmark_id for navigation
        if hunk_block.type == "deletion" then
            hunk_block.extmark_id = vim.api.nvim_buf_set_extmark(
                self.state.bufnr,
                self.highlights.namespace_diff,
                virt_line_row,
                0,
                extmark_opts
            )
            hunk_block.del_extmark_id = hunk_block.extmark_id
        else
            -- For changes, just add virtual lines (extmark_id already set above)
            hunk_block.del_extmark_id = vim.api.nvim_buf_set_extmark(
                self.state.bufnr,
                self.highlights.namespace_diff,
                virt_line_row,
                0,
                extmark_opts
            )
        end
    end
end

--- Calculate proper placement for virtual lines handling file boundaries
---@param hunk_block  DiffHunk block to calculate placement for
---@return integer virt_line_row The row to place the virtual line
---@return boolean virt_lines_above Whether to place virtual lines above the target line
function EditUI:_calculate_virtual_line_placement(hunk_block)
    local file_line_count = vim.api.nvim_buf_line_count(self.state.bufnr)
    local target_line = hunk_block.applied_start_line - 1 -- Convert to 0-based

    -- At start of file (line 0 or 1)
    if target_line <= 0 then
        if #hunk_block.new_lines > 0 then
            return #hunk_block.new_lines - 1, false -- Place at line 0, above (since below doesn't work at start)
        end
        return 0, false -- Place at line 0, below (since above doesn't work at start)
    end

    -- At end of file
    if target_line >= file_line_count then
        return file_line_count - 1, false -- Place at last line, below
    end

    -- Middle of file - place above the target line
    return target_line, true
end

-- Set up keybindings for diff operations (hunk-based)
function EditUI:_setup_keybindings()
    local bufnr = self.state.bufnr

    local KEYBINDINGS = self.config.keybindings

    -- Store original keymaps before setting temporary ones
    self.state.original_keymaps = keymap_utils.store_original_keymaps("n", KEYBINDINGS, bufnr)

    -- Accept current change
    vim.keymap.set({ "n" }, KEYBINDINGS.accept, function()
        self:_accept_current_hunk()
    end, { buffer = bufnr, desc = "Accept current hunk" })

    -- Reject current change
    vim.keymap.set({ "n" }, KEYBINDINGS.reject, function()
        self:_reject_current_hunk()
    end, { buffer = bufnr, desc = "Reject current hunk" })

    -- Navigate to next hunk
    vim.keymap.set({ "n" }, KEYBINDINGS.next, function()
        self:_navigate_next_hunk()
    end, { buffer = bufnr, desc = "Go to next hunk" })

    -- Navigate to previous hunk
    vim.keymap.set({ "n" }, KEYBINDINGS.prev, function()
        self:_navigate_prev_hunk()
    end, { buffer = bufnr, desc = "Go to previous hunk" })

    -- Accept all remaining changes
    vim.keymap.set({ "n" }, KEYBINDINGS.accept_all, function()
        self:_accept_all_remaining_hunks()
    end, { buffer = bufnr, desc = "Accept all remaining hunks" })

    -- Reject all remaining changes
    vim.keymap.set({ "n" }, KEYBINDINGS.reject_all, function()
        self:_reject_all_remaining_hunks()
    end, { buffer = bufnr, desc = "Reject all remaining hunks" })
end

-- Set up autocommands for buffer events
function EditUI:_setup_autocmds()
    local bufnr = self.state.bufnr

    -- Update hints on cursor movement
    vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
        buffer = bufnr,
        group = self.state.augroup,
        callback = vim.schedule_wrap(function()
            self:_update_hints()
        end),
    })

    -- Handle buffer save
    vim.api.nvim_create_autocmd({ "BufWritePost" }, {
        buffer = bufnr,
        group = self.state.augroup,
        callback = vim.schedule_wrap(function()
            self:_handle_save()
        end),
    })

    -- Handle buffer close
    vim.api.nvim_create_autocmd({ "BufUnload", "BufWipeout" }, {
        buffer = bufnr,
        group = self.state.augroup,
        callback = vim.schedule_wrap(function()
            self:_handle_buffer_close()
        end),
    })
end

-- Accept all remaining hunks
function EditUI:_accept_all_remaining_hunks()
    if not self.state.hunk_blocks then
        return self:_complete_session()
    end

    for _, hunk in ipairs(self.state.hunk_blocks) do
        if not self.state.completed_hunks[hunk.hunk_id] then
            self:_accept_current_hunk(hunk)
        end
    end
    self:_complete_session()
end

-- Reject all remaining hunks
function EditUI:_reject_all_remaining_hunks()
    if not self.state.hunk_blocks then
        return self:_complete_session()
    end

    for _, hunk in ipairs(self.state.hunk_blocks) do
        if not (self.state.completed_hunks and self.state.completed_hunks[hunk.hunk_id]) then
            self:_reject_current_hunk(hunk)
        end
    end
    self:_complete_session()
end

function EditUI:write_if_modified()
    local file = self.state.file_path
    local buf_state = vim.bo[self.state.bufnr]
    if file and (buf_state and buf_state.modified) then
        local ok, err = pcall(vim.cmd.write, file)
        if not ok and err:match("E212") then
            local dir = vim.fn.fnamemodify(file, ":h")
            if vim.fn.isdirectory(dir) == 0 then
                vim.fn.mkdir(dir, "p")
            end
            vim.cmd.write(file)
        end
    end
end

-- Navigate to next hunk
---@return boolean success True if navigated to next hunk
function EditUI:_navigate_next_hunk()
    if not self.state.hunk_blocks then
        return false
    end

    local current_index = self.state.current_hunk_index or 1

    -- Find next uncompleted hunk
    for i = current_index + 1, #self.state.hunk_blocks do
        local hunk = self.state.hunk_blocks[i]
        if not (self.state.completed_hunks and self.state.completed_hunks[hunk.hunk_id]) then
            if self:_navigate_to_hunk(i) then
                self.state.current_hunk_index = i
                return true
            end
        end
    end

    -- Wrap to beginning
    for i = 1, current_index do
        local hunk = self.state.hunk_blocks[i]
        if not (self.state.completed_hunks and self.state.completed_hunks[hunk.hunk_id]) then
            if self:_navigate_to_hunk(i) then
                self.state.current_hunk_index = i
                return true
            end
        end
    end

    return false -- No more hunks
end

-- Navigate to previous hunk
---@return boolean success True if navigated to previous hunk
function EditUI:_navigate_prev_hunk()
    if not self.state.hunk_blocks then
        return false
    end

    local current_index = self.state.current_hunk_index or 1

    -- Find previous uncompleted hunk
    for i = current_index - 1, 1, -1 do
        local hunk = self.state.hunk_blocks[i]
        if not (self.state.completed_hunks and self.state.completed_hunks[hunk.hunk_id]) then
            if self:_navigate_to_hunk(i) then
                self.state.current_hunk_index = i
                return true
            end
        end
    end

    -- Wrap to end
    for i = #self.state.hunk_blocks, current_index + 1, -1 do
        local hunk = self.state.hunk_blocks[i]
        if not (self.state.completed_hunks and self.state.completed_hunks[hunk.hunk_id]) then
            if self:_navigate_to_hunk(i) then
                self.state.current_hunk_index = i
                return true
            end
        end
    end

    return false -- No more hunks
end

-- Validate hunk block and return location info to avoid duplicate extmark fetching
---@param hunk_block table Hunk block to validate
---@return table result Validation result with location info
function EditUI:_validate_hunk_block(hunk_block)
    -- Check if extmark_id exists
    if not hunk_block.extmark_id then
        return {
            status = "no_extmark_id",
            navigable = false,
            start_row = hunk_block.deletion_position or hunk_block.applied_start_line or 0,
            end_row = hunk_block.deletion_position or hunk_block.applied_end_line or 0,
        }
    end

    local extmark_details = vim.api.nvim_buf_get_extmark_by_id(
        self.state.bufnr,
        self.highlights.namespace_diff,
        hunk_block.extmark_id,
        { details = true }
    )

    -- Return both validation and location info
    local start_row = extmark_details[1] or 0
    local end_row = extmark_details[3] and extmark_details[3].end_row or start_row

    local result = {
        start_row = start_row,
        end_row = end_row,
        extmark_details = extmark_details,
    }

    -- Check if extmark exists
    if #extmark_details == 0 then
        result.status = "extmark_missing"
        result.navigable = false
        return result
    end

    -- Special handling for pure deletions
    if hunk_block.type == "deletion" then
        -- For deletions, extmark should point to virtual line with deletion marker
        result.status = "deletion_marker_present"
        result.navigable = true
        result.end_row = start_row -- Same line for deletion marker
        return result
    end

    -- Check if hunk was deleted (start == end but we expect multiple lines)
    if start_row == end_row and #hunk_block.new_lines > 1 then
        result.status = "content_deleted"
        result.navigable = false
        return result
    end

    -- Get current content in the range for additions and changes
    local current_lines = vim.api.nvim_buf_get_lines(self.state.bufnr, start_row, end_row, false)

    -- Check content status
    if vim.deep_equal(current_lines, hunk_block.new_lines) then
        result.status = "matches_new"
        result.navigable = true
    elseif vim.deep_equal(current_lines, hunk_block.old_lines) then
        result.status = "matches_old"
        result.navigable = true
    else
        result.status = "user_modified"
        result.navigable = true
    end
    return result
end

-- Navigate to specific hunk using validation result (avoids duplicate extmark fetching)
---@param hunk_index integer Hunk index to navigate to
---@return boolean success True if navigation was successful
function EditUI:_navigate_to_hunk(hunk_index)
    if not self.state.hunk_blocks then
        return false
    end

    local hunk_block = self.state.hunk_blocks[hunk_index]
    if not hunk_block then
        return false
    end

    local validation = self:_validate_hunk_block(hunk_block)
    if not validation.navigable then
        -- Skip this hunk, try next
        return self:_find_next_navigable_hunk(hunk_index)
    end

    -- Use validation.start_row directly, no need to fetch extmark again
    local winid = self:_get_window_for_buffer()
    if winid then
        vim.api.nvim_win_set_cursor(winid, { validation.start_row + 1, 0 })
        vim.api.nvim_win_call(winid, function()
            vim.cmd("normal! zz")
        end)
        return true
    end

    return false
end

-- Reject current hunk using validation result (avoids duplicate extmark fetching)
---@param hunk_block table? Optional specific hunk to reject
function EditUI:_reject_current_hunk(hunk_block)
    local target_hunk = hunk_block or self:_get_current_hunk()
    if not target_hunk then
        return
    end

    local validation = self:_validate_hunk_block(target_hunk)
    if not validation.navigable then
        -- Hunk is not available, just mark as completed
        self.state.completed_hunks[target_hunk.hunk_id] = "skipped"
        return
    end

    -- Handle different hunk types for rejection
    if target_hunk.type == "deletion" then
        -- For deletions, we need to restore the deleted content
        -- Insert the old lines at the deletion position
        local insert_pos = target_hunk.deletion_position or validation.start_row
        vim.api.nvim_buf_set_lines(
            self.state.bufnr,
            insert_pos - 1,
            insert_pos - 1, -- Insert without replacing
            false,
            target_hunk.old_lines
        )
    elseif target_hunk.type == "addition" then
        -- For additions, remove the added lines
        vim.api.nvim_buf_set_lines(
            self.state.bufnr,
            validation.start_row,
            validation.end_row,
            false,
            {} -- Remove lines
        )
    else
        -- For changes, replace new content with old content
        vim.api.nvim_buf_set_lines(
            self.state.bufnr,
            validation.start_row,
            validation.end_row,
            false,
            target_hunk.old_lines
        )
    end

    -- Mark as rejected and remove highlights
    self.state.completed_hunks = self.state.completed_hunks or {}
    self.state.completed_hunks[target_hunk.hunk_id] = "rejected"
    self:_remove_hunk_highlights(target_hunk)
    if not self:_navigate_next_hunk() then
        return self:_complete_session()
    end
end

-- Accept current hunk (just remove highlights and mark as accepted)
---@param hunk_block table? Optional specific hunk to accept
function EditUI:_accept_current_hunk(hunk_block)
    local target_hunk = hunk_block or self:_get_current_hunk()
    if not target_hunk then
        return
    end

    -- Mark as accepted and remove highlights
    self.state.completed_hunks = self.state.completed_hunks or {}
    self.state.completed_hunks[target_hunk.hunk_id] = "accepted"
    self:_remove_hunk_highlights(target_hunk)
    if not self:_navigate_next_hunk() then
        return self:_complete_session()
    end
end

-- Find next navigable hunk starting from given index
---@param current_index integer Current hunk index
---@return boolean success True if found and navigated to next hunk
function EditUI:_find_next_navigable_hunk(current_index)
    if not self.state.hunk_blocks then
        return false
    end

    -- Search forward from current position
    for i = current_index + 1, #self.state.hunk_blocks do
        local hunk_block = self.state.hunk_blocks[i]
        if not self.state.completed_hunks[hunk_block.hunk_id] then
            local validation = self:_validate_hunk_block(hunk_block)
            if validation.navigable then
                return self:_navigate_to_hunk(i)
            end
        end
    end

    -- Wrap around to beginning
    for i = 1, current_index do
        local hunk_block = self.state.hunk_blocks[i]
        if not self.state.completed_hunks[hunk_block.hunk_id] then
            local validation = self:_validate_hunk_block(hunk_block)
            if validation.navigable then
                return self:_navigate_to_hunk(i)
            end
        end
    end

    return false -- No more navigable hunks
end

-- Get current hunk based on cursor position
---@return DiffHunk? Current hunk block or nil if not found
function EditUI:_get_current_hunk()
    if not self.state.hunk_blocks then
        return
    end

    local winid = self:_get_window_for_buffer()
    if not winid then
        return
    end

    local cursor_line = vim.api.nvim_win_get_cursor(winid)[1] - 1

    for _, hunk_block in ipairs(self.state.hunk_blocks) do
        if self.state.completed_hunks[hunk_block.hunk_id] then
            goto continue
        end

        local validation = self:_validate_hunk_block(hunk_block)
        if validation.navigable then
            if cursor_line >= validation.start_row and cursor_line <= validation.end_row then
                return hunk_block
            end
        end

        ::continue::
    end
end

-- Remove highlights for a specific hunk
---@param hunk_block DiffHunk Hunk block to remove highlights from
function EditUI:_remove_hunk_highlights(hunk_block)
    if hunk_block.extmark_id then
        pcall(vim.api.nvim_buf_del_extmark, self.state.bufnr, self.highlights.namespace_diff, hunk_block.extmark_id)
        hunk_block.extmark_id = nil
    end
    if hunk_block.del_extmark_id then
        pcall(vim.api.nvim_buf_del_extmark, self.state.bufnr, self.highlights.namespace_diff, hunk_block.del_extmark_id)
        hunk_block.extmark_id = nil
    end
    -- Clear current hint for the removed block's line
    vim.api.nvim_buf_clear_namespace(self.state.bufnr, self.highlights.namespace_hints, 0, -1)
end

-- Get window ID for the buffer
---@return integer? winid Window ID or nil if not found
function EditUI:_get_window_for_buffer()
    for _, winid in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_get_buf(winid) == self.state.bufnr then
            return winid
        end
    end
    return nil
end

-- Restore original content for a block
---@param block LocatedBlock Block to restore
function EditUI:_restore_block_original_content(block)
    local start_line = block.applied_start_line or 1
    local end_line = block.applied_end_line or 1
    vim.api.nvim_buf_set_lines(self.state.bufnr, start_line - 1, end_line, false, block.location_result.found_lines)

    -- Update the block's position after restoration
    block.applied_end_line = start_line + #block.location_result.found_lines - 1
end

-- Update hint display (hunk-based)
function EditUI:_update_hints()
    if not self.state or not self.state.hunk_blocks then
        return
    end

    vim.api.nvim_buf_clear_namespace(self.state.bufnr, self.highlights.namespace_hints, 0, -1)
    local current_hunk = self:_get_current_hunk()
    if not current_hunk then
        return
    end

    -- For all hunks of a block, show the block confidence
    local confidence = current_hunk.confidence or 0
    local current_index = self.state.current_hunk_index or 1
    local index = string.format("%d/%d", current_index, #self.state.hunk_blocks)

    -- Get position from hunk validation for accurate placement
    local validation = self:_validate_hunk_block(current_hunk)
    local start_line = math.max(0, validation.start_row)

    -- If at start of buffer, place hint at a visible location
    if start_line == 0 then
        start_line = math.max(1, validation.end_row or 1)
    end
    local file_line_count = vim.api.nvim_buf_line_count(self.state.bufnr)
    -- -- At end of file
    if start_line >= file_line_count - 1 then
        start_line = file_line_count
    end

    vim.api.nvim_buf_set_extmark(self.state.bufnr, self.highlights.namespace_hints, start_line - 1, 0, {
        virt_text = self:_create_hint_line(confidence, index),
        virt_text_pos = "right_align",
        priority = self.highlights.priority,
    })
end

-- Handle buffer save
function EditUI:_handle_save()
    -- If there are still pending hunks, treat save as accept all
    local has_pending = #vim.tbl_filter(function(hunk)
        return not self.state.completed_hunks[hunk.hunk_id]
    end, self.state.hunk_blocks) > 0

    if has_pending then
        return self:_accept_all_remaining_hunks()
    end
    self:_complete_session()
end

-- Handle buffer close
function EditUI:_handle_buffer_close()
    if not self.state or self.state.has_completed then
        return
    end
    self.state.callbacks.on_cancel("User closed the editor without accepting the changes.")
end

-- Complete the editing session
function EditUI:_complete_session()
    if not self.state or self.state.has_completed then
        return
    end
    self.state.has_completed = true
    self:write_if_modified()
    vim.schedule(function()
        local origin_winnr = self.state.origin_winnr
        -- Signal completion to the session without arguments
        self.state.callbacks.on_complete()
        if self.config.go_to_origin_on_complete and origin_winnr and vim.api.nvim_win_is_valid(origin_winnr) then
            pcall(vim.api.nvim_set_current_win, origin_winnr)
        end
    end)
end

--- Generate block-focused summary for LLM
--- @param final_content string Final content after edits
--- @param config table Configuration options for summary generation
--- @return string Summary of block results formatted for markdown
function EditUI:_generate_block_summary(final_content, config)
    -- Handle case where no hunk blocks were generated (no actual changes)
    if not self.state.hunk_blocks or #self.state.hunk_blocks == 0 then
        return string.format(
            "No changes were applied in `%s` file. Because, REPLACE content of all provided SEARCH/REPLACE block(s) was found identical to the content found at that location",
            self.state.file_path
        )
    end

    -- Analyze block results
    local block_results = self:_analyze_block_results()

    -- Count block statuses
    local fully_applied = 0
    local partially_applied = 0
    local fully_rejected = 0

    for _, result in pairs(block_results) do
        if result.status == "FULLY_APPLIED" then
            fully_applied = fully_applied + 1
        elseif result.status == "PARTIALLY_APPLIED" then
            partially_applied = partially_applied + 1
        else
            fully_rejected = fully_rejected + 1
        end
    end

    local total_blocks = fully_applied + partially_applied + fully_rejected
    local summary = ""

    -- Simple messages for straightforward cases
    if fully_applied == total_blocks then
        summary = string.format("All %d block(s) were successfully applied to `%s`", total_blocks, self.state.file_path)
    elseif fully_rejected == total_blocks then
        summary = string.format(
            "All %d block(s) were rejected - no changes were applied to `%s`",
            total_blocks,
            self.state.file_path
        )
    else
        -- Detailed breakdown for mixed results
        local applied_count = fully_applied + partially_applied
        summary = string.format(
            "%d of %d block(s) were applied to `%s`\n\n",
            applied_count,
            total_blocks,
            self.state.file_path
        )

        -- Add details for each block in order
        local sorted_blocks = {}
        for block_id, result in pairs(block_results) do
            table.insert(sorted_blocks, result)
        end
        table.sort(sorted_blocks, function(a, b)
            return a.block_id < b.block_id
        end)

        for _, result in ipairs(sorted_blocks) do
            summary = summary .. self:_format_block_result(result) .. "\n\n"
        end
    end

    -- Always add final diff
    if config.include_final_diff then
        summary = summary .. self:_create_final_diff_section(final_content)
    end

    return summary
end

--- Analyze hunk results grouped by parent blocks
---@return table<integer, table> block_results
function EditUI:_analyze_block_results()
    local block_results = {}

    -- Group hunks by parent block
    for _, hunk in ipairs(self.state.hunk_blocks) do
        local parent_id = hunk.parent_id
        if not block_results[parent_id] then
            block_results[parent_id] = {
                block_id = parent_id,
                rejected_lines = {},
                total_hunks = 0,
                accepted_hunks = 0,
            }
        end

        block_results[parent_id].total_hunks = block_results[parent_id].total_hunks + 1

        local status = self.state.completed_hunks[hunk.hunk_id] or "accepted"
        if status == "accepted" then
            block_results[parent_id].accepted_hunks = block_results[parent_id].accepted_hunks + 1
        else
            block_results[parent_id].rejected_lines = vim.deepcopy(hunk.new_lines)
        end
    end

    -- Determine status for each block
    for _, result in pairs(block_results) do
        if result.accepted_hunks == result.total_hunks then
            result.status = "FULLY_APPLIED"
        elseif result.accepted_hunks == 0 then
            result.status = "REJECTED"
        else
            result.status = "PARTIALLY_APPLIED"
        end
    end

    return block_results
end

--- Format individual block result for summary
--- @param result table Block result containing status and details
--- @return string Formatted block result for markdown
function EditUI:_format_block_result(result)
    if result.status == "FULLY_APPLIED" then
        return string.format("### %s: FULLY APPLIED\nAll changes from this block were accepted.", result.block_id)
    elseif result.status == "REJECTED" then
        return string.format("### %s: REJECTED\nAll changes from this block were rejected.", result.block_id)
    else
        -- PARTIALLY_APPLIED
        local rejected_content = table.concat(result.rejected_lines, "\n")
        return string.format(
            "### %s: PARTIALLY APPLIED\nThe following lines from your REPLACE content were NOT accepted by the user:\n```\n%s\n```",
            result.block_id,
            rejected_content
        )
    end
end

---Create final diff section only for edits
---@param final_content string Final content after edits
---@param original_content string? Original content (fallback to state if not provided)
---@return string Final diff section formatted for markdown
function EditUI:_create_final_diff_section(final_content, original_content)
    local function add_new_lines(content)
        if content:sub(-1) ~= "\n" then
            return content .. "\n"
        end
        return content
    end

    -- Use provided original content or fallback to state
    local orig_content = original_content or self.state.original_content

    -- Avoiding diff generation if the entire file is being replaced
    if self.state.is_replacing_entire_file then
        return ""
    end

    local diff_output = vim.trim(
        vim.diff(add_new_lines(orig_content), add_new_lines(final_content), { result_type = "unified", ctxlen = 1 })
            or ""
    )

    return string.format(
        "\n\n### BEFORE vs AFTER EDIT SESSION DIFF for `%s`:\nIMPORTANT: Carefully observe this diff to understand the changes applied in the edit session including user edits or formatters etc \n```diff\n%s\n```",
        self.state.file_path,
        diff_output
    )
end

--- Add diagnostic feedback to the summary
--- @param summary string Initial summary text
--- @param config table Configuration options for diagnostics
--- @param callback function Callback to execute with the final summary
function EditUI:_add_diagnostic_feedback(summary, config, callback)
    local lsp_feedback = ""
    local bufnr = self.state.bufnr
    local file_path = self.state.file_path
    if not config.send_diagnostics then
        return callback(summary)
    end
    vim.defer_fn(function()
        local min_severity = config.diagnostic_severity or vim.diagnostic.severity.WARN
        local all_diagnostics = vim.diagnostic.get(bufnr)
        local diagnostics = vim.tbl_filter(function(diag)
            return diag.severity <= min_severity
        end, all_diagnostics)
        if #diagnostics > 0 then
            lsp_feedback = string.format("\n\n## CURRENT DIAGNOSTICS FOR `%s` :\n", file_path)

            -- Get file content for context
            local file_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

            -- Group diagnostics by line number
            local diag_by_line = {}
            for _, diag in ipairs(diagnostics) do
                local line_num = diag.lnum + 1 -- Convert to 1-based
                if not diag_by_line[line_num] then
                    diag_by_line[line_num] = {}
                end
                table.insert(diag_by_line[line_num], diag)
            end

            -- Format each line with its diagnostics
            for line_num in vim.spairs(diag_by_line) do
                local line_content = file_lines[line_num] or ""
                local number = string.format("%d ", line_num)
                lsp_feedback = lsp_feedback .. string.format("\n%s| %s\n", number, line_content)

                for _, diag in ipairs(diag_by_line[line_num]) do
                    lsp_feedback = lsp_feedback
                        .. string.format(
                            string.rep(" ", #number) .. "| %s (%s from %s)\n",
                            diag.message or "No message",
                            vim.diagnostic.severity[diag.severity],
                            diag.source or "Unknown"
                        )
                end
            end
        end
        callback(summary .. lsp_feedback)
    end, config.wait_for_diagnostics or 0)
end

-- Generate comprehensive summary of the editing session
---@param config table Options including final_content, original_content, config
---@param callback function Callback to receive the summary string
function EditUI:get_summary(config, callback)
    if not self.state then
        return callback("")
    end

    local file_lines = vim.api.nvim_buf_get_lines(self.state.bufnr, 0, -1, false)
    local final_content = table.concat(file_lines, "\n")

    local summary_parts = {}

    -- Generate session summary if enabled
    if config.include_session_summary then
        local session_summary = self:_generate_block_summary(final_content, config)
        if session_summary and session_summary ~= "" then
            table.insert(summary_parts, session_summary)
        end
    end

    local base_summary = table.concat(summary_parts, "\n\n")

    -- Add diagnostic feedback if enabled (asynchronous)
    if config.send_diagnostics then
        self:_add_diagnostic_feedback(base_summary, config, callback)
    else
        callback(base_summary)
    end
end

-- Cleanup UI resources
function EditUI:cleanup()
    if not self.state then
        return
    end

    local bufnr = self.state.bufnr

    -- Clear namespaces
    if vim.api.nvim_buf_is_valid(bufnr) then
        vim.api.nvim_buf_clear_namespace(bufnr, self.highlights.namespace_diff, 0, -1)
        vim.api.nvim_buf_clear_namespace(bufnr, self.highlights.namespace_hints, 0, -1)

        -- Restore original keymaps and clean up temporary ones
        if self.state.original_keymaps then
            keymap_utils.restore_keymaps("n", self.config.keybindings, bufnr, self.state.original_keymaps)
        end
    end

    -- Clean up autocommands
    pcall(vim.api.nvim_del_augroup_by_id, self.state.augroup)

    self.state = nil
end

--- Create a hint line for the current hunk
--- @param confidence number Confidence percentage of the current hunk
--- @param progress string Progress string in the format "current/total"
--- @return table Hint line as a table of text segments with highlights
function EditUI:_create_hint_line(confidence, progress)
    local KEYBINDINGS = self.config.keybindings
    local hint_line = {}
    local hl_type = confidence < 100 and "warn" or "success"
    table.insert(hint_line, { "", text.highlights[hl_type] })
    table.insert(hint_line, {
        string.format(" %d%% │ %s ", confidence, progress),
        text.highlights[hl_type .. "_fill"],
    })

    local full_line = string.format(
        " accept (%s) reject (%s) accept-all (%s) reject-all (%s) ",
        KEYBINDINGS.accept,
        KEYBINDINGS.reject,
        KEYBINDINGS.accept_all,
        KEYBINDINGS.reject_all
    )
    table.insert(hint_line, { full_line, "ColorColumn" })
    table.insert(hint_line, { "", text.highlights[hl_type] })
    return hint_line
end

return EditUI
