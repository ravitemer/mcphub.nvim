local M = {}
local NuiLine = require("mcphub.utils.nuiline")
local State = require("mcphub.state")
local Text = require("mcphub.utils.text")
local async = require("plenary.async")
local constants = require("mcphub.utils.constants")

---@param title string Title of the floating window
---@param content string Content to be displayed in the floating window
---@param on_save fun(new_content:string) Callback function to be called when the user saves the content
---@param opts {filetype?: string, validate?: function, show_footer?: boolean, start_insert?: boolean, on_cancel?: function, position?: "cursor"|"center", go_to_placeholder?: boolean, virtual_lines?: Array[]} Options for the floating window
function M.multiline_input(title, content, on_save, opts)
    opts = opts or {}
    local bufnr = vim.api.nvim_create_buf(false, true)
    local cursor = vim.api.nvim_win_get_cursor(0)
    local width = vim.api.nvim_win_get_width(0)
    local max_width = 70
    width = math.min(width, max_width) - 3

    -- Set buffer options
    vim.api.nvim_buf_set_option(bufnr, "buftype", "nofile")
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
    local auto_height = #lines + #(opts.virtual_lines or {}) + 1
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
        style = "minimal",
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

    -- Override positioning if center is requested
    if opts.position == "center" then
        win_opts.relative = "editor"
        win_opts.bufpos = nil
        win_opts.row = 1
        win_opts.col = math.floor((vim.o.columns - width) / 2)
    end

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
                virt_text = { { "[<i> Edit, <Cr> Save]", "Comment" } },
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

    -- Add virtual lines if provided
    if opts.virtual_lines and #opts.virtual_lines > 0 then
        local virt_ns = vim.api.nvim_create_namespace("mcphub_multiline_virtual")
        local original_line_count = #vim.split(content or "", "\n")
        local virt_lines = {}

        local divider = string.rep("-", width - 2)
        table.insert(virt_lines, { { divider, "Comment" } })
        for _, l in ipairs(opts.virtual_lines) do
            table.insert(virt_lines, vim.islist(l) and { l } or { { l, "Comment" } })
        end
        vim.api.nvim_buf_set_extmark(bufnr, virt_ns, original_line_count - 1, 0, {
            virt_lines = virt_lines,
            priority = 2000,
        })
    end

    -- Handle cursor positioning
    if opts.go_to_placeholder then
        -- Find first ${} placeholder and position cursor there
        local content_lines = vim.split(content or "", "\n")
        for i, line in ipairs(content_lines) do
            local start_pos = line:find("%${")
            if start_pos then
                vim.api.nvim_win_set_cursor(win, { i, start_pos - 1 })
                break
            end
        end
    elseif opts.start_insert ~= false then
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
        win_opts.border = vim.o.winborder ~= "" and vim.o.winborder
            or { "╭", "─", "╮", "│", "╯", "─", "╰", "│" }
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

---@param server_name string Name of the server being authorized
---@param auth_url string Authorization URL
function M.open_auth_popup(server_name, auth_url)
    local width = 80 -- Wider to accommodate wrapped text

    -- Create content using NuiLine for proper highlighting
    local info_lines = {
        Text.pad_line(
            NuiLine():append("Browser should open automatically with the authorization page.", Text.highlights.text)
        ),
        Text.pad_line(NuiLine():append("If not, you can use this URL:", Text.highlights.text)),
        Text.pad_line(NuiLine():append(auth_url, Text.highlights.link)),
        Text.empty_line(),
        Text.pad_line(
            NuiLine():append(
                "If you're running mcphub on a remote machine, paste the redirect URL below",
                Text.highlights.muted
            )
        ),
        Text.pad_line(
            NuiLine():append(
                string.format("(looks like 'http://localhost...?code=...&server_name=%s')", server_name),
                Text.highlights.muted
            )
        ),
        Text.empty_line(),
        Text.pad_line(
            NuiLine():append(
                "This popup will automatically close once authentication is successful.",
                Text.highlights.muted
            )
        ),
    }

    local info_height = #info_lines + 4
    local input_height = 1

    -- Position at top center
    local row = 1
    local col = math.floor((vim.o.columns - width) / 2)

    -- Create buffers
    local info_buf = vim.api.nvim_create_buf(false, true)
    local input_buf = vim.api.nvim_create_buf(false, true)

    -- Create namespace for virtual text
    local ns = vim.api.nvim_create_namespace("MCPHubAuthPopup")

    -- Info window configuration
    local info_opts = {
        relative = "editor",
        width = width,
        height = info_height,
        row = row,
        col = col,
        style = "minimal",
        title = string.format(Text.icons.unauthorized .. " Authorize %s ", server_name),
        title_pos = "center",
    }

    local input_title = " > Callback URL"
    -- Input window configuration
    local input_opts = {
        relative = "editor",
        width = width,
        height = input_height,
        row = row + info_height + 2,
        col = col,
        style = "minimal",
        title = input_title,
    }

    -- Set info content with proper highlighting
    vim.api.nvim_buf_set_option(info_buf, "modifiable", true)
    for i, line in ipairs(info_lines) do
        line:render(info_buf, ns, i)
    end
    vim.api.nvim_buf_set_option(info_buf, "modifiable", false)
    vim.api.nvim_buf_set_option(info_buf, "buftype", "nofile")

    -- Create windows
    local info_win = vim.api.nvim_open_win(info_buf, true, info_opts)
    local input_win = vim.api.nvim_open_win(input_buf, false, input_opts)

    -- Set window options
    for _, win in ipairs({ info_win, input_win }) do
        vim.api.nvim_win_set_option(win, "wrap", true)
        vim.api.nvim_win_set_option(win, "cursorline", false)
    end

    local function update_virtual_text(text, hl)
        vim.api.nvim_buf_clear_namespace(input_buf, ns, 0, -1)
        pcall(vim.api.nvim_buf_set_extmark, input_buf, ns, 0, 0, {
            virt_text = { { text, hl } },
            virt_text_pos = "right_align",
        })
    end
    update_virtual_text("[<Cr> submit, <Tab> Cycle]", Text.highlights.muted)

    -- Track current window
    local current_win = info_win

    -- Setup autocmd to close both windows
    local function close_windows()
        if vim.api.nvim_win_is_valid(info_win) then
            vim.api.nvim_win_close(info_win, true)
        end
        if vim.api.nvim_win_is_valid(input_win) then
            vim.api.nvim_win_close(input_win, true)
        end
        -- Return focus to MCPHub window
        if State.ui_instance and State.ui_instance.window then
            vim.api.nvim_set_current_win(State.ui_instance.window)
        end
    end

    local function switch_window()
        if current_win == info_win and vim.api.nvim_win_is_valid(input_win) then
            vim.api.nvim_set_current_win(input_win)
            current_win = input_win
            vim.cmd("startinsert")
        elseif current_win == input_win and vim.api.nvim_win_is_valid(info_win) then
            vim.api.nvim_set_current_win(info_win)
            current_win = info_win
            vim.cmd("stopinsert")
        end
    end
    -- Basic validation for the URL
    local function validate_url(url)
        if not url or vim.trim(url) == "" then
            return false, "Invalid URL format"
        end

        -- Check for required parameters
        if not url:match("code=[^&]+") then
            return false,
                "Missing 'code' parameter. The redirect url should look like 'http://localhost?code=...&server_name=...'."
        end
        if not url:match("server_name=[^&]+") then
            return false,
                "Missing 'server_name' parameter. The redirect url should look like 'http://localhost?code=...&server_name=...'."
        end

        return true
    end

    -- Set up auto-close on server update
    local update_handler = "MCPHubAuthPopup" .. server_name
    vim.api.nvim_create_augroup(update_handler, { clear = true })
    vim.api.nvim_create_autocmd("User", {
        pattern = "MCPHubServersUpdated",
        group = update_handler,
        callback = function()
            local server = State.hub_instance:get_server(server_name)
            if server and server.status ~= constants.ConnectionStatus.UNAUTHORIZED then
                close_windows()
                return true
            end
        end,
    })

    -- Handle input
    local function handle_submit()
        local lines = vim.api.nvim_buf_get_lines(input_buf, 0, -1, false)
        local url = vim.trim(table.concat(lines, "\n"))

        if url == "" then
            vim.notify("Please enter a callback URL", vim.log.levels.WARN)
            return
        end

        local valid, err = validate_url(url)
        if not valid then
            vim.notify(err, vim.log.levels.ERROR)
            return
        end

        local function update_input_title(text, hl)
            local ok, config = pcall(vim.api.nvim_win_get_config, input_win)
            if ok then
                config.title = { { " " .. text .. " ", hl } }
                vim.api.nvim_win_set_config(input_win, config)
            end
        end

        update_input_title(" Authorizing...", Text.highlights.info)
        update_virtual_text("Validating callback URL...", Text.highlights.info)
        State.hub_instance:handle_oauth_callback(url, function(response, err)
            if err then
                vim.notify("OAuth callback failed: " .. err, vim.log.levels.ERROR)
            else
                vim.notify(response.message, vim.log.levels.INFO)
            end
            update_input_title(input_title, Text.highlights.info)
            update_virtual_text("Press <Cr> to submit", Text.highlights.comment)
        end)
    end

    -- Set up keymaps
    local function setup_keymaps(buf)
        local keymaps = {
            ["<CR>"] = handle_submit,
            ["<Esc>"] = close_windows,
            ["q"] = close_windows,
            ["<Tab>"] = switch_window,
        }

        for key, handler in pairs(keymaps) do
            vim.keymap.set("n", key, handler, { buffer = buf, nowait = true })
            vim.keymap.set("i", key, handler, { buffer = buf, nowait = true })
        end
    end

    setup_keymaps(info_buf)
    setup_keymaps(input_buf)

    -- Set up buffer cleanup
    for _, buf in ipairs({ info_buf, input_buf }) do
        vim.api.nvim_create_autocmd("BufWipeout", {
            buffer = buf,
            callback = close_windows,
            once = true,
        })
    end
    switch_window()
end

return M
