local M = {}
local Text = require("mcphub.utils.text")

function M.multiline_input(title, content, on_save, on_cancel)
    -- Create a new scratch buffer
    local bufnr = vim.api.nvim_create_buf(false, true)

    --get current cursor
    local cursor = vim.api.nvim_win_get_cursor(0)
    --get current window width
    local width = vim.api.nvim_win_get_width(0)

    -- Set buffer options
    vim.api.nvim_buf_set_option(bufnr, "buftype", "acwrite")
    vim.api.nvim_buf_set_option(bufnr, "bufhidden", "wipe")
    vim.api.nvim_buf_set_option(bufnr, "swapfile", false)

    -- Set initial content
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.split(content or "", "\n"))

    -- Calculate window size and position
    -- local width = 80
    local height = 8
    local max_width = 70
    width = math.min(width, max_width) - 3
    -- local editor_width = vim.o.columns
    -- local editor_height = vim.o.lines

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
        footer = {
            { " ", nil },
            { " <Cr> ", Text.highlights.header_btn },
            { ": Submit | ", nil },
            { " <Esc> ", Text.highlights.header_btn },
            { ",", nil },
            { " q ", Text.highlights.header_btn },
            { ": Cancel ", nil },
        },
    }

    -- Create floating window
    local win = vim.api.nvim_open_win(bufnr, true, win_opts)

    -- Set window options
    vim.api.nvim_win_set_option(win, "number", false)
    vim.api.nvim_win_set_option(win, "relativenumber", false)
    vim.api.nvim_win_set_option(win, "wrap", true)
    vim.api.nvim_win_set_option(win, "cursorline", true)

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
        -- Close the window
        vim.api.nvim_win_close(win, true)
        -- -- Call save callback if content changed
        -- if content ~= new_content then
        on_save(new_content)
        -- end
    end

    local function close_window()
        vim.api.nvim_win_close(win, true)
        if on_cancel then
            on_cancel()
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

    vim.cmd("startinsert")
    vim.api.nvim_win_set_cursor(win, { last_line_nr, last_col + 1 })
    update_virtual_text() -- Show initial hint
    --start insert mode
end

return M
