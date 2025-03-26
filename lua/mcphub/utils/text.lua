---@brief [[
--- Text utilities for MCPHub
--- Provides text formatting, layout, and rendering utilities
---@brief ]]
local NuiLine = require("mcphub.utils.nuiline")
local NuiText = require("mcphub.utils.nuitext")
local hl = require("mcphub.utils.highlights")

local M = {}

-- Constants
M.HORIZONTAL_PADDING = 2

-- Export highlight groups for easy access
M.highlights = hl.groups

M.icons = {

    tower = "󰐻",
    tool = "",
    resourceTemplate = "",
    resource = "",
    circle = "○",
    circleFilled = "●",
    bug = "",
    event = "",
    favorite = "",
    loaded = "●",
    not_loaded = "○",
    arrowRight = "➜",
    triangleDown = "▼",
    triangleRight = "▶",
    search = "",
    tag = "",
    sort = "",
    octoface = "",
    check = "✔",
    gear = "",
    loading = "",
    downArrow = "",
    uninstall = "",
    sparkles = "✨",
    download = "",
    install = "",
    link = "",
    pencil = "󰏫",
    edit = "󰏫",
    instructions = "",

    -- Error type icons
    setup_error = "",
    server_error = "",
    runtime_error = "",
    general_error = "",

    error = "",
    warn = "",
    info = "",
    question = "",
    hint = "",
    debug = "",
    trace = "✎",
}

--- Split text into multiple NuiLines while preserving newlines
---@param content string Text that might contain newlines
---@param highlight? string Optional highlight group
---@return NuiLine[]
function M.multiline(content, highlight)
    if type(content) ~= "string" then
        content = tostring(content)
    end
    local lines = {}
    for _, line in
        ipairs(vim.split(content, "\n", {
            plain = true,
        }))
    do
        table.insert(lines, NuiLine():append(line, highlight))
    end
    return lines
end

--- Add horizontal padding to a line
---@param line NuiLine|string The line to pad
---@param highlight? string Optional highlight for string input
---@param padding? number Override default padding
---@return NuiLine
function M.pad_line(line, highlight, padding)
    local nui_line = NuiLine():append(string.rep(" ", padding or M.HORIZONTAL_PADDING))

    if type(line) == "string" then
        nui_line:append(line, highlight)
    else
        nui_line:append(line)
    end

    return nui_line:append(string.rep(" ", padding or M.HORIZONTAL_PADDING))
end

--- Create empty line with consistent padding
---@return NuiLine
function M.empty_line()
    return M.pad_line("")
end

--- Create a divider line
---@param width number Total width
---@param is_full? boolean Whether to ignore padding
---@return NuiLine
function M.divider(width, is_full)
    if is_full then
        return NuiLine():append(string.rep("-", width), M.highlights.muted)
    end
    return M.pad_line(string.rep("-", width - (M.HORIZONTAL_PADDING * 2)), M.highlights.muted)
end

--- Align text with proper padding
---@param text string|NuiLine Text to align
---@param width number Available width
---@param align "left"|"center"|"right" Alignment direction
---@param highlight? string Optional highlight for text
---@return NuiLine
function M.align_text(text, width, align, highlight)
    local inner_width = width - (M.HORIZONTAL_PADDING * 2)

    -- Convert string to NuiLine if needed
    local line = type(text) == "string" and NuiLine():append(text, highlight) or text
    local line_width = line:width()

    -- Calculate padding
    local padding = math.max(0, inner_width - line_width)
    local left_pad = align == "center" and math.floor(padding / 2) or align == "right" and padding or 0
    -- local right_pad = align == "center" and math.ceil(padding / 2) or align == "left" and padding or 0

    -- Create padded line
    return NuiLine():append(string.rep(" ", M.HORIZONTAL_PADDING + left_pad)):append(line)
    -- :append(string.rep(" ", right_pad + M.HORIZONTAL_PADDING))
end

---@param label string
---@param shortcut string
---@param selected boolean
---@return NuiLine
function M.create_button(label, shortcut, selected)
    local line = NuiLine()
    -- Start button group
    if selected then
        -- Selected button has full background
        line:append(" " .. shortcut, M.highlights.header_btn_shortcut)
        line:append(" " .. label .. " ", M.highlights.header_btn)
    else
        -- Unselected shows just shortcut highlighted
        line:append(" " .. shortcut, M.highlights.header_shortcut)
        line:append(" " .. label .. " ", M.highlights.header)
    end
    return line
end

--- Create centered tab bar with selected state
---@param tabs {text: string, selected: boolean}[] Array of tab objects
---@param width number Total width available
---@return NuiLine
function M.create_tab_bar(tabs, width)
    -- Create tab group first
    local tab_group = NuiLine()
    for i, tab in ipairs(tabs) do
        if i > 1 then
            tab_group:append(" ")
        end
        tab_group:append(" " .. tab.text .. " ", tab.selected and M.highlights.header_accent or M.highlights.header)
    end

    -- Create the entire line with centered tab group
    return M.align_text(tab_group, width, "center")
end

--- The MCP Hub logo
---@param width number Window width for centering
---@return NuiLine[]
function M.render_logo(width)
    local logo_lines = {
        "╔╦╗╔═╗╔═╗  ╦ ╦╦ ╦╔╗ ",
        "║║║║  ╠═╝  ╠═╣║ ║╠╩╗",
        "╩ ╩╚═╝╩    ╩ ╩╚═╝╚═╝",
    }
    local lines = {}
    for _, line in ipairs(logo_lines) do
        table.insert(lines, M.align_text(line, width, "center", M.highlights.title))
    end
    return lines
end

--- Create header with buttons
---@param width number Window width
---@param current_view string Currently selected view
---@return NuiLine[]
function M.render_header(width, current_view)
    local lines = M.render_logo(width)

    -- Create buttons line
    local buttons = NuiLine()

    -- Add buttons with proper padding
    local btn_list = {
        {
            key = "H",
            label = "Hub",
            view = "main",
        },
        {
            key = "M",
            label = "Marketplace",
            view = "marketplace",
        },
        {
            key = "C",
            label = "Config",
            view = "config",
        },
        {
            key = "L",
            label = "Logs",
            view = "logs",
        },
        {
            key = "?",
            label = "Help",
            view = "help",
        },
    }

    for i, btn in ipairs(btn_list) do
        if i > 1 then
            buttons:append("  ") -- Add spacing between buttons
        end
        buttons:append(M.create_button(btn.label, btn.key, current_view == btn.view))
    end

    -- Center the buttons line
    local padding = math.floor((width - buttons:width()) / 2)
    if padding > 0 then
        table.insert(lines, NuiLine():append(string.rep(" ", padding)):append(buttons))
    else
        table.insert(lines, buttons)
    end

    return lines
end

return M
