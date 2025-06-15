local Path = require("plenary.path")

-- Core write file logic
local function handle_write_file(req, res)
    if not req.params.path or not req.params.content or req.params.content == vim.NIL then
        return res:error("Missing required parameters: path and content")
    end
    local p = Path:new(req.params.path)
    local path = p:absolute()
    local contents = req.params.content or ""

    -- Ensure parent directories exist
    p:touch({ parents = true })

    -- Get original content if file exists
    local original_content = ""
    if p:exists() then
        original_content = p:read()
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
    vim.api.nvim_win_set_buf(target_win, bufnr)
    vim.api.nvim_buf_set_option(bufnr, "buflisted", true)

    -- Set content and mark as modified
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.split(contents, "\n"))
    vim.bo[bufnr].modified = true
    -- Check if we should auto-approve
    if vim.g.mcphub_auto_approve == true then
        vim.cmd("write")
        -- Return to original window if it's still valid
        if vim.api.nvim_win_is_valid(current_win) then
            vim.api.nvim_set_current_win(current_win)
        end
        res:text("Successfully written: " .. path):send()
        return
    end

    -- Create diff view for manual approval
    if vim.api.nvim_win_get_width(target_win) < 70 then
        vim.cmd("split")
    else
        vim.cmd("vsplit")
    end
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
    end

    local function capture_changes()
        local current_content = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
        changes_diff = vim.diff(contents, current_content, {
            result_type = "unified",
        })
    end

    local function send_response(accepted)
        if not response_sent then
            response_sent = true
            if accepted then
                local msg = "Successfully written: " .. path
                if changes_diff and changes_diff ~= "" then
                    msg = msg .. "\n\nUser-made the following changes:\n```diff\n" .. changes_diff .. "\n```"
                end
                res:text(msg):send()
            else
                res:text("User rejected the file changes: " .. path):send()
            end
        end
    end

    local function handle_post_write()
        if response_sent then
            return
        end
        capture_changes()
        file_accepted = true
        send_response(true)
        cleanup_diff()
    end

    local function handle_reject()
        if response_sent then
            return
        end
        file_accepted = false
        send_response(false)
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.split(original_content, "\n"))
        vim.cmd("write")
        cleanup_diff()
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

---@type MCPTool
return {
    name = "write_file",
    description = "Write content to a file",
    inputSchema = {
        type = "object",
        properties = {
            path = {
                type = "string",
                description = "Path to the file to write",
            },
            content = {
                type = "string",
                description = "Content to write to the file",
            },
        },
        required = { "path", "content" },
    },
    handler = handle_write_file,
}
