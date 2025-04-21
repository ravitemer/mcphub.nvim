local M = {}
local Text = require("mcphub.utils.text")

function M.multiline_input(title, content, on_save, opts)
    opts = opts or {}
    local bufnr = vim.api.nvim_create_buf(false, true)
    local cursor = vim.api.nvim_win_get_cursor(0)
    local width = vim.api.nvim_win_get_width(0)
    local max_width = 70
    width = math.min(width, max_width) - 3

    -- Set buffer options
    vim.api.nvim_buf_set_option(bufnr, "buftype", "acwrite")
    vim.api.nvim_buf_set_option(bufnr, "bufhidden", "wipe")
    vim.api.nvim_buf_set_option(bufnr, "swapfile", false)
    if opts.filetype then
        vim.api.nvim_buf_set_option(bufnr, "filetype", opts.filetype)
    else
        vim.api.nvim_buf_set_option(bufnr, "filetype", "text")
    end

    local lines = vim.split(content or "", "\n")
    -- Set initial content
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    local height = 8
    local auto_height = #lines + 1
    if auto_height > height then
        height = math.min(auto_height, vim.api.nvim_win_get_height(0) - 2)
    end

    local win_opts = {
        relative = "win",
        bufpos = cursor,
        width = width,
        focusable = true,
        height = height,
        anchor = "NW",
        -- col = math.floor((editor_width - width) / 2),
        -- row = math.floor((editor_height - height) / 2),
        style = "minimal",
        border = "rounded",
        title = { { " " .. title .. " ", Text.highlights.title } },
        title_pos = "center",
        footer = opts.show_footer ~= false and {
            { " ", nil },
            { " <Cr> ", Text.highlights.title },
            { ": Submit | ", Text.highlights.muted },
            { " <Esc> ", Text.highlights.title },
            { ",", Text.highlights.muted },
            { " q ", Text.highlights.title },
            { ": Cancel ", Text.highlights.muted },
        } or "",
    }

    -- Create floating window
    local win = vim.api.nvim_open_win(bufnr, true, win_opts)

    -- Set window options
    vim.api.nvim_win_set_option(win, "number", false)
    vim.api.nvim_win_set_option(win, "relativenumber", false)
    vim.api.nvim_win_set_option(win, "wrap", false)
    vim.api.nvim_win_set_option(win, "cursorline", false)

    -- Create namespace for virtual text
    local ns = vim.api.nvim_create_namespace("MCPHubMultiLineInput")

    -- Function to update virtual text at cursor position
    local function update_virtual_text()
        vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
        if vim.fn.mode() == "n" then
            local cursor = vim.api.nvim_win_get_cursor(0)
            local row = cursor[1] - 1
            vim.api.nvim_buf_set_extmark(bufnr, ns, row, 0, {
                virt_text = { { "Press <CR> to save", "Comment" } },
                virt_text_pos = "eol",
            })
        end
    end

    -- Set up autocmd for cursor movement and mode changes
    local group = vim.api.nvim_create_augroup("MCPHubMultiLineInputCursor", { clear = true })
    vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI", "ModeChanged" }, {
        buffer = bufnr,
        group = group,
        callback = update_virtual_text,
    })

    -- Set buffer local mappings
    local function save_and_close()
        local new_content = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
        new_content = vim.trim(new_content)
        if opts.validate then
            local valid = opts.validate(new_content)
            if not valid then
                return
            end
        end
        -- Close the window
        vim.api.nvim_win_close(win, true)
        -- -- Call save callback if content changed
        -- if content ~= new_content then
        on_save(new_content)
        -- end
    end

    local function close_window()
        vim.api.nvim_win_close(win, true)
        if opts.on_cancel then
            opts.on_cancel()
        end
    end

    -- Add mappings for normal mode
    local mappings = {
        ["<CR>"] = save_and_close,
        ["<Esc>"] = close_window,
        ["q"] = close_window,
    }
    -- Apply mappings
    for key, action in pairs(mappings) do
        vim.keymap.set("n", key, action, { buffer = bufnr, silent = true })
    end

    local last_line_nr = vim.api.nvim_buf_line_count(bufnr)
    local last_line = vim.api.nvim_buf_get_lines(bufnr, last_line_nr - 1, last_line_nr, false)[1] -- zero-indexed, exclusive end

    local last_col = string.len(last_line)

    if opts.start_insert ~= false then
        vim.cmd("startinsert")
        vim.api.nvim_win_set_cursor(win, { last_line_nr, last_col + 1 })
    end
    update_virtual_text() -- Show initial hint
end

function M.is_visual_mode()
    local mode = vim.fn.mode()
    return mode == "v" or mode == "V" or mode == "^V"
end

function M.get_selection(bufnr)
    bufnr = bufnr or vim.api.nvim_get_current_buf()
    local mode = vim.fn.mode()
    local start_pos, end_pos
    if M.is_visual_mode() then
        start_pos = vim.fn.getpos("v")
        end_pos = vim.fn.getpos(".")
    else
        start_pos = vim.fn.getpos("'<")
        end_pos = vim.fn.getpos("'>")
    end

    local start_line = start_pos[2]
    local start_col = start_pos[3]
    local end_line = end_pos[2]
    local end_col = end_pos[3]

    if start_line > end_line or (start_line == end_line and start_col > end_col) then
        start_line, end_line = end_line, start_line
        start_col, end_col = end_col, start_col
    end
    local lines = vim.api.nvim_buf_get_lines(bufnr, start_line - 1, end_line, false)
    if start_line == 0 then
        lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
        start_line = 1
        start_col = 0
        end_line = #lines
        end_col = #lines[#lines]
    end
    if #lines > 0 then
        if mode == "V" or (not is_in_visual_mode and vim.fn.visualmode() == "V") then
            start_col = 1
            end_col = #lines[#lines]
        else
            if #lines == 1 then
                lines[1] = lines[1]:sub(start_col, end_col)
            else
                lines[1] = lines[1]:sub(start_col)
                lines[#lines] = lines[#lines]:sub(1, end_col)
            end
        end
    end
    return {
        lines = lines,
        start_line = start_line,
        start_col = start_col,
        end_line = end_line,
        end_col = end_col,
    }
end

return M
