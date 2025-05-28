local M = {}
local NuiLine = require("mcphub.utils.nuiline")
local Text = require("mcphub.utils.text")
local async = require("plenary.async")

---@param title string Title of the floating window
---@param content string Content to be displayed in the floating window
---@param on_save fun(new_content:string) Callback function to be called when the user saves the content
---@param opts {filetype?: string, validate?: function, show_footer?: boolean, start_insert?: boolean, on_cancel?: function} Options for the floating window
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
        if M.is_visual_mode() then
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

---Create a confirmation window with Yes/No/Cancel options
---@param message string | string[] | NuiLine[] Message to display
---@param opts? {relative_to_chat?: boolean, min_width?: number, max_width?: number}
---@return boolean, boolean -- (confirmed, cancelled)
function M.confirm(message, opts)
    opts = opts or {}

    local result = async.wrap(function(callback)
        if not message or #message == 0 then
            return callback(false, true)
        end

        -- Track active option (default to "yes")
        local active_option = "yes"

        -- Function to create footer with current active state
        local function create_footer()
            return {
                { " ", Text.highlights.seamless_border },
                {
                    " Yes ",
                    active_option == "yes" and Text.highlights.button_active or Text.highlights.button_inactive,
                },
                { " • ", Text.highlights.seamless_border },
                { " No ", active_option == "no" and Text.highlights.button_active or Text.highlights.button_inactive },
                { " • ", Text.highlights.seamless_border },
                {
                    " Cancel ",
                    active_option == "cancel" and Text.highlights.button_active or Text.highlights.button_inactive,
                },
                { " ", Text.highlights.seamless_border },
            }
        end

        -- Function to update footer
        local function update_footer(win)
            if vim.api.nvim_win_is_valid(win) then
                local config = vim.api.nvim_win_get_config(win)
                config.footer = create_footer()
                vim.api.nvim_win_set_config(win, config)
            end
        end

        -- Process message into lines
        local lines = {}
        if type(message) == "string" then
            lines = Text.multiline(message)
        else
            if vim.islist(message) then
                for _, line in ipairs(message) do
                    if type(line) == "string" then
                        vim.list_extend(lines, Text.multiline(line))
                    elseif vim.islist(line) then
                        local n_line = NuiLine()
                        for _, part in ipairs(line) do
                            if type(part) == "string" then
                                n_line:append(part)
                            else
                                n_line:append(unpack(part))
                            end
                        end
                        table.insert(lines, n_line)
                    else
                        local n_line = NuiLine()
                        n_line:append(line)
                        table.insert(lines, n_line)
                    end
                end
            end
        end

        -- Calculate optimal window dimensions
        local min_width = opts.min_width or 50
        local max_width = opts.max_width or 80
        local content_width = 0

        -- Find the longest line for width calculation
        for _, line in ipairs(lines) do
            local line_width = type(line) == "string" and #line or line:width()
            content_width = math.max(content_width, line_width)
        end

        -- Add padding and ensure reasonable bounds
        local width = math.max(min_width, math.min(max_width, content_width + 8))
        local height = math.min(#lines + 3, math.floor(vim.o.lines * 0.6)) -- +3 for padding and title

        -- Determine positioning - top center of editor
        local win_opts = M.get_window_position(width, height)

        -- Create buffer and set content
        local bufnr = vim.api.nvim_create_buf(false, true)
        local ns_id = vim.api.nvim_create_namespace("MCPHubConfirmPrompt")

        -- Add some padding at the top
        table.insert(lines, 1, NuiLine():append(""))

        -- Render content with proper padding
        for i, line in ipairs(lines) do
            if type(line) == "string" then
                line = Text.pad_line(line)
            elseif line._texts then
                -- This is a NuiLine object, pad it properly
                line = Text.pad_line(line)
            else
                -- This might be an array format, convert it to NuiLine first
                local nui_line = NuiLine()
                if vim.islist(line) then
                    for _, part in ipairs(line) do
                        if type(part) == "string" then
                            nui_line:append(part)
                        elseif vim.islist(part) then
                            nui_line:append(part[1], part[2])
                        end
                    end
                else
                    nui_line:append(tostring(line))
                end
                line = Text.pad_line(nui_line)
            end
            line:render(bufnr, ns_id, i)
        end

        -- Enhanced window options with better styling
        win_opts.style = "minimal"
        win_opts.border = { "╭", "─", "╮", "│", "╯", "─", "╰", "│" }
        win_opts.title_pos = "center"
        win_opts.title = {
            { " MCPHUB Confirmation ", Text.highlights.header_btn },
        }
        win_opts.footer = create_footer()
        win_opts.footer_pos = "center"

        -- Create the window
        local win = vim.api.nvim_open_win(bufnr, true, win_opts)

        -- Enhanced window styling
        vim.api.nvim_win_set_option(win, "wrap", true)
        vim.api.nvim_win_set_option(win, "cursorline", false)

        -- Set buffer options
        vim.api.nvim_buf_set_option(bufnr, "modifiable", false)
        vim.api.nvim_buf_set_option(bufnr, "buftype", "nofile")
        vim.api.nvim_buf_set_option(bufnr, "swapfile", false)

        local is_closed = false

        -- Enhanced close function with cleanup
        local function close_window(confirmed, cancelled)
            if is_closed then
                return
            end
            is_closed = true

            vim.schedule(function()
                if vim.api.nvim_win_is_valid(win) then
                    if vim.api.nvim_win_is_valid(win) then
                        vim.api.nvim_win_close(win, true)
                    end
                end
                callback(confirmed, cancelled)
            end)
        end

        -- Function to execute active option
        local function execute_active_option()
            if active_option == "yes" then
                close_window(true, false)
            elseif active_option == "no" then
                close_window(false, false)
            else -- cancel
                close_window(false, true)
            end
        end

        -- Set up keymaps with visual feedback and navigation
        local keymaps = {
            -- Direct actions
            ["y"] = function()
                close_window(true, false)
            end,
            ["Y"] = function()
                close_window(true, false)
            end,
            ["n"] = function()
                close_window(false, false)
            end,
            ["N"] = function()
                close_window(false, false)
            end,
            ["c"] = function()
                close_window(false, true)
            end,
            ["C"] = function()
                close_window(false, true)
            end,
            ["<Esc>"] = function()
                close_window(false, true)
            end,
            ["q"] = function()
                close_window(false, true)
            end,
            ["<CR>"] = execute_active_option, -- Execute the currently active option
            -- Tab navigation
            ["<Tab>"] = function()
                if active_option == "yes" then
                    active_option = "no"
                elseif active_option == "no" then
                    active_option = "cancel"
                else
                    active_option = "yes"
                end
                update_footer(win)
            end,
        }

        for key, handler in pairs(keymaps) do
            vim.keymap.set("n", key, handler, {
                buffer = bufnr,
                nowait = true,
                silent = true,
                desc = "MCPHub confirm: " .. key,
            })
        end

        -- Auto-close protection
        local group = vim.api.nvim_create_augroup("MCPHubConfirm" .. bufnr, { clear = true })
        vim.api.nvim_create_autocmd({ "WinClosed", "BufWipeout" }, {
            buffer = bufnr,
            group = group,
            callback = function()
                close_window(false, true)
            end,
            once = true,
        })

        -- Focus the window and ensure it's visible
        vim.api.nvim_set_current_win(win)
        -- Ensure we're in normal mode for key navigation
        vim.cmd("stopinsert")
        vim.cmd("redraw")
    end, 1)

    return result()
end

-- Helper function to determine window positioning
---@param width number
---@param height number
---@return table window_opts
function M.get_window_position(width, height)
    local win_opts = {
        width = width,
        height = height,
        focusable = true,
        relative = "editor",
        row = 1, -- Just 1 line from the top
        col = math.floor((vim.o.columns - width) / 2), -- Center horizontally
    }

    return win_opts
end

return M
