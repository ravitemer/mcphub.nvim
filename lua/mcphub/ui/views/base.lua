---[[
--- Base view for MCPHub UI
--- Provides common view functionality and base for view inheritance
---]]
local NuiLine = require("mcphub.utils.nuiline")
local State = require("mcphub.state")
local Text = require("mcphub.utils.text")
local ns_id = vim.api.nvim_create_namespace("MCPHub")
local renderer = require("mcphub.utils.renderer")

local VIEW_TYPES = {
    SETUP_INDEPENDENT = { "logs", "help", "config" },
}

---@class View
---@field ui MCPHub.UI Parent UI instance
---@field name string View name
---@field keymaps table<string, {action: function, desc: string}> View-specific keymaps
---@field active_keymaps string[] Currently active keymap keys
---@field cursor_pos number[]|nil Last known cursor position
---@field interactive_lines { line: number, type: string, context: any }[] List of interactive lines
---@field hover_ns number Namespace for highlighting
---@field cursor_highlight number|nil Extmark ID for current highlight
---@field cursor_group number|nil Cursor movement tracking group
local View = {}
View.__index = View

function View:new(ui, name)
    local instance = {
        ui = ui,
        name = name or "unknown",
        keymaps = {},
        active_keymaps = {},
        cursor_pos = nil,
        interactive_lines = {},
        hover_ns = vim.api.nvim_create_namespace("MCPHub" .. name .. "Hover"),
        cursor_highlight = nil,
        cursor_group = nil,
    }
    return setmetatable(instance, self)
end

--- Get initial cursor position for this view
function View:get_initial_cursor_position()
    -- By default, position after header's divider
    local lines = self:render_header()
    if #lines > 0 then
        return #lines
    end
    return 1
end

--- Track current cursor position
function View:track_cursor()
    if self.ui.window and vim.api.nvim_win_is_valid(self.ui.window) then
        self.cursor_pos = vim.api.nvim_win_get_cursor(0)
    end
end

--- Set cursor position with bounds checking
---@param pos number[]|nil Position to set [line, col] or nil for last tracked position
---@param opts? {restore_col: boolean} Options for cursor setting (default: {restore_col: true})
function View:set_cursor(pos, opts)
    -- Use provided position or last tracked position
    local cursor = pos or self.cursor_pos
    if not cursor then
        return
    end
    -- Ensure window is valid
    if not (self.ui.window and vim.api.nvim_win_is_valid(self.ui.window)) then
        return
    end
    -- Ensure line is within bounds
    local line_count = vim.api.nvim_buf_line_count(self.ui.buffer)
    local new_pos = { math.min(cursor[1], line_count), cursor[2] }
    -- Set cursor
    vim.api.nvim_win_set_cursor(self.ui.window, new_pos)
end

--- Register a view-specific keymap
---@param key string Key to map
---@param action function Action to perform
---@param desc string Description for which-key
function View:add_keymap(key, action, desc)
    self.keymaps[key] = {
        action = action,
        desc = desc,
    }
end

--- Apply all registered keymaps
function View:apply_keymaps()
    local buffer = self.ui.buffer
    self:clear_keymaps()

    -- Apply view's registered keymaps
    for key, map in pairs(self.keymaps) do
        vim.keymap.set("n", key, map.action, {
            buffer = buffer,
            desc = map.desc,
            nowait = true,
        })
        table.insert(self.active_keymaps, key)
    end
end

function View:clear_keymaps()
    for _, key in ipairs(self.active_keymaps) do
        pcall(vim.keymap.del, "n", key, {
            buffer = self.ui.buffer,
        })
    end
    self.active_keymaps = {} -- Clear the active keymaps array after deletion
end

--- Save cursor position before leaving
function View:save_cursor_position()
    if self.ui.window and vim.api.nvim_win_is_valid(self.ui.window) then
        self.ui.cursor_states[self.name] = vim.api.nvim_win_get_cursor(0)
    end
end

--- Restore cursor position after entering
function View:restore_cursor_position()
    if not (self.ui.window and vim.api.nvim_win_is_valid(self.ui.window)) then
        return
    end

    local saved_pos = self.ui.cursor_states[self.name]
    local line_count = vim.api.nvim_buf_line_count(self.ui.buffer)
    if saved_pos then
        -- Ensure position is valid
        local new_pos = { math.min(saved_pos[1], line_count), saved_pos[2] }
        vim.api.nvim_win_set_cursor(0, new_pos)
    else
        -- Use initial position if no saved position
        local initial_line = self:get_initial_cursor_position()
        if initial_line then
            local new_pos = { math.min(initial_line, line_count), 2 }
            vim.api.nvim_win_set_cursor(0, new_pos)
        end
    end
end

--- Called before view is drawn (override in child views)
function View:before_enter() end

--- Called after view is drawn and applied
function View:after_enter()
    -- Add cursor movement autocmd
    self.cursor_group = vim.api.nvim_create_augroup("MCPHub" .. self.name .. "Cursor", {
        clear = true,
    })
    vim.api.nvim_create_autocmd("CursorMoved", {
        group = self.cursor_group,
        buffer = self.ui.buffer,
        callback = function()
            self:handle_cursor_move()
        end,
    })

    self:apply_keymaps()
    self:restore_cursor_position()
end

--- Called before leaving view (override in child views)
function View:before_leave()
    self:save_cursor_position()
end

--- Called after leaving view
function View:after_leave()
    -- Clean up cursor tracking
    if self.cursor_group then
        vim.api.nvim_del_augroup_by_name("MCPHub" .. self.name .. "Cursor")
        self.cursor_group = nil
    end

    -- Clear highlight
    if self.cursor_highlight then
        vim.api.nvim_buf_del_extmark(self.ui.buffer, self.hover_ns, self.cursor_highlight)
        self.cursor_highlight = nil
    end

    self:clear_keymaps()
end

-- Line tracking functionality
function View:track_line(line_nr, type, context)
    table.insert(self.interactive_lines, {
        line = line_nr,
        type = type,
        context = context,
    })
end

function View:clear_line_tracking()
    self.interactive_lines = {}
end

---@param line_nr number
---@return string?, table?
function View:get_line_info(line_nr)
    for _, tracked in ipairs(self.interactive_lines) do
        if tracked.line == line_nr then
            return tracked.type, tracked.context
        end
    end
    return nil, nil
end

function View:handle_cursor_move()
    -- Clear previous highlight
    if self.cursor_highlight then
        vim.api.nvim_buf_del_extmark(self.ui.buffer, self.hover_ns, self.cursor_highlight)
        self.cursor_highlight = nil
    end

    -- Get current line
    local cursor = vim.api.nvim_win_get_cursor(0)
    local line = cursor[1]

    -- Get line info
    local type, context = self:get_line_info(line)
    if type then
        -- Add virtual text without line highlight
        self.cursor_highlight = vim.api.nvim_buf_set_extmark(self.ui.buffer, self.hover_ns, line - 1, 0, {
            virt_text = { { context and context.hint or "[<l> Interact]", Text.highlights.muted } },
            virt_text_pos = "eol",
        })
    end
end

--- Whether the view should show setup errors
---@return boolean
function View:should_show_setup_error()
    -- Don't show setup errors in certain views
    for _, name in ipairs(VIEW_TYPES.SETUP_INDEPENDENT) do
        if self.name == name then
            return false
        end
    end
    return true
end

--- Get window width for centering
function View:get_width()
    return vim.api.nvim_win_get_width(self.ui.window)
end

-- Add divider
function View:divider(is_full)
    return Text.divider(self:get_width(), is_full)
end

--- Create an empty line
function View:line()
    local line = NuiLine():append(string.rep(" ", self:get_width()))
    return line
end

function View:center(line, highlight)
    return Text.align_text(line, self:get_width(), "center", highlight)
end

--- Render header for view
--- @return NuiLine[] Header lines
function View:render_header(add_new_line)
    add_new_line = add_new_line == nil and true or add_new_line
    local lines = Text.render_header(self:get_width(), self.ui.current_view)
    table.insert(lines, self:divider())
    if add_new_line then
        table.insert(lines, self:line())
    end
    return lines
end

--- Render setup error state
---@param lines NuiLine[] Existing lines
---@return NuiLine[] Updated lines
function View:render_setup_error(lines)
    table.insert(lines, Text.pad_line(NuiLine():append("Setup Failed:", Text.highlights.error)))

    for _, err in ipairs(State:get_errors()) do
        vim.list_extend(lines, renderer.render_error(err))
        table.insert(lines, Text.empty_line())
    end

    return lines
end

--- Render progress state
---@param lines NuiLine[] Existing lines
---@return NuiLine[] Updated lines
function View:render_setup_progress(lines)
    -- Show progress message
    table.insert(lines, Text.align_text("Setting up MCPHub...", self:get_width(), "center", Text.highlights.info))
    return vim.list_extend(lines, renderer.render_server_entries(State.server_output.entries))
end

--- Render footer with keymaps
--- @return NuiLine[] Lines for footer
function View:render_footer()
    local lines = {}

    -- Add padding and divider
    table.insert(lines, Text.empty_line())
    table.insert(lines, self:divider(true))

    -- Get all keymaps
    local key_items = {}

    -- Add view-specific keymaps first
    for key, map in pairs(self.keymaps or {}) do
        table.insert(key_items, {
            key = key,
            desc = map.desc,
        })
    end

    table.insert(key_items, {
        key = "r",
        desc = "Refresh",
    })
    table.insert(key_items, {
        key = "R",
        desc = "Restart",
    })
    -- Add common close
    table.insert(key_items, {
        key = "q",
        desc = "Close",
    })

    -- Format in a single line
    local keys_line = NuiLine()
    for i, key in ipairs(key_items) do
        if i > 1 then
            keys_line:append("  ", Text.highlights.muted)
        end
        keys_line
            :append(" " .. key.key .. " ", Text.highlights.header_shortcut)
            :append(" ", Text.highlights.muted)
            :append(key.desc, Text.highlights.muted)
    end

    table.insert(lines, Text.pad_line(keys_line))

    return lines
end

--- Render view content
--- Should be overridden by child views
--- @return NuiLine[] Lines to render
function View:render()
    -- Get base header
    local lines = self:render_header()

    -- Handle special states
    if State.setup_state == "failed" then
        if self:should_show_setup_error() then
            return self:render_setup_error(lines)
        end
    elseif State.setup_state == "in_progress" then
        if self:should_show_setup_error() then
            return self:render_setup_progress(lines)
        end
    end

    -- Views should override this to provide content
    table.insert(lines, Text.pad_line(NuiLine():append("No content implemented for this view", Text.highlights.muted)))

    return lines
end

function View:lock()
    vim.api.nvim_buf_set_option(self.ui.buffer, "modifiable", false)
end

function View:unlock()
    vim.api.nvim_buf_set_option(self.ui.buffer, "modifiable", true)
end

function View:open()
    return self.ui.window and vim.api.nvim_win_is_valid(self.ui.window)
end

--- Draw view content to buffer
function View:draw()
    if not self:open() then
        return
    end

    -- Track cursor position before drawing
    self:track_cursor()

    -- Get buffer
    local buf = self.ui.buffer

    -- Reset view state
    self:clear_line_tracking()
    if self.cursor_highlight then
        vim.api.nvim_buf_del_extmark(self.ui.buffer, self.hover_ns, self.cursor_highlight)
        self.cursor_highlight = nil
    end

    -- Make buffer modifiable
    vim.api.nvim_buf_set_option(buf, "modifiable", true)

    -- Clear buffer
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {})

    -- Get content and footer lines
    local lines = self:render()
    local footer_lines = self:render_footer()

    -- Calculate if we need padding
    local win_height = vim.api.nvim_win_get_height(self.ui.window)
    local content_height = #lines
    local total_needed = win_height - content_height - #footer_lines

    -- Add padding if needed
    if total_needed > 0 then
        for _ = 1, total_needed do
            table.insert(lines, Text.empty_line())
        end
    end

    -- Add footer at the end
    vim.list_extend(lines, footer_lines)

    -- Render each line with proper highlights
    local line_idx = 1
    for _, line in ipairs(lines) do
        if type(line) == "string" then
            -- Handle string lines with potential newlines
            for _, l in ipairs(Text.multiline(line)) do
                ---@diagnostic disable-next-line: undefined-field
                l:render(buf, ns_id, line_idx)
                line_idx = line_idx + 1
            end
        else
            ---@diagnostic disable-next-line: undefined-field
            line:render(buf, ns_id, line_idx)
            line_idx = line_idx + 1
        end
    end

    -- Make buffer unmodifiable
    vim.api.nvim_buf_set_option(buf, "wrap", true)
    vim.api.nvim_buf_set_option(buf, "modifiable", false)

    -- Restore cursor position after drawing
    self:set_cursor()
end

return View
