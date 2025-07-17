---@brief [[
--- Text utilities for MCPHub
--- Provides text formatting, layout, and rendering utilities
---@brief ]]
local NuiLine = require("mcphub.utils.nuiline")
local hl = require("mcphub.utils.highlights")

local M = {}

-- Constants
M.HORIZONTAL_PADDING = 2

-- Export highlight groups for easy access
M.highlights = hl.groups

M.icons = {

    hourglass = "",
    person = "",
    clock = "",
    server = "󰒋",
    antenna = "󰖩",
    antenna_off = "󰖪",
    sse = "",
    auto = "󰁪",
    tower = "󰐻",
    tool = "",
    resourceTemplate = "",
    resource = "",
    circle = "○",
    circleFilled = "●",
    bug = "",
    event = "",
    param = "",
    favorite = "",
    loaded = "●",
    vertical_bar = "│",
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
    plus = "",
    instructions = "",
    unauthorized = "󱅞",

    file = "",
    folder = "",
    globe = "",
    prompt = "󰿠",
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
    local line = type(text) == "string" and NuiLine():append(text, highlight) or text --[[@as NuiLine]]
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
        tab_group:append(
            " " .. tab.text .. " ",
            tab.selected and M.highlights.button_active or M.highlights.button_inactive
        )
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

--- Render markdown text with proper syntax highlighting
---@param text string The markdown text to render
---@return NuiLine[]
function M.render_markdown(text)
    if not text then
        return {}
    end

    local lines = {}
    local in_code_block = false

    for _, line in ipairs(vim.split(text, "\n", { plain = true })) do
        local nui_line = NuiLine()

        -- Handle code blocks
        if line:match("^```") then
            in_code_block = not in_code_block
            nui_line:append(line, M.highlights.muted)

        -- Inside code block
        elseif in_code_block then
            nui_line:append(line, M.highlights.code)

        -- Headers
        elseif line:match("^#+ ") then
            local level = #line:match("^(#+)")
            local header_text = line:match("^#+%s+(.+)")
            nui_line:append(string.rep("#", level) .. " ", M.highlights.muted):append(header_text, M.highlights.title)

        -- Lists
        elseif line:match("^%s*[-*] ") then
            local indent = #(line:match("^%s*") or "")
            local list_text = line:match("^%s*[-*]%s+(.+)")
            nui_line
                :append(string.rep(" ", indent))
                :append("• ", M.highlights.muted)
                :append(list_text, M.highlights.text)

        -- Normal text
        else
            nui_line:append(line, M.highlights.text)
        end

        table.insert(lines, M.pad_line(nui_line))
    end

    return lines
end

--- Render JSON with syntax highlighting using the existing pretty_json formatter
---@param text string|table? The JSON text or table to render
---@param opts table Optional options
---@return NuiLine[]
function M.render_json(text, opts)
    local utils = require("mcphub.utils")

    -- Convert table to JSON if needed
    if type(text) == "table" then
        text = vim.json.encode(text)
    end

    -- Use the existing pretty printer
    local formatted = utils.pretty_json(text or "", opts)
    local lines = {}

    -- Process each line and add highlighting
    for _, line in ipairs(vim.split(formatted, "\n", { plain = true })) do
        local nui_line = NuiLine()
        local pos = 1

        -- Add indentation
        local indent = line:match("^(%s*)")
        if indent then
            nui_line:append(indent)
            pos = #indent + 1
        end

        -- Handle property names (with quotes) first
        local property = line:match('^%s*"([^"]+)"%s*:', pos)
        if property then
            nui_line:append('"' .. property .. '"', M.highlights.json_property)
            pos = pos + #property + 2 -- +2 for quotes
            -- Skip past the colon
            local colon_pos = line:find(":", pos)
            if colon_pos then
                nui_line:append(line:sub(pos, colon_pos), M.highlights.json_punctuation)
                pos = colon_pos + 1
            end
        end

        -- Process the rest of the line
        while pos <= #line do
            local char = line:sub(pos, pos)

            -- Handle structural characters
            if char:match("[{%[%]}:,]") then
                nui_line:append(char, M.highlights.json_punctuation)
            -- Handle string values (must be in quotes)
            elseif char == '"' then
                local str_end = pos + 1
                while str_end <= #line do
                    if line:sub(str_end, str_end) == '"' and line:sub(str_end - 1, str_end - 1) ~= "\\" then
                        break
                    end
                    str_end = str_end + 1
                end
                nui_line:append(line:sub(pos, str_end), M.highlights.json_string)
                pos = str_end
            -- Handle numbers
            elseif char:match("%d") then
                local num = line:match("%d+%.?%d*", pos)
                if num then
                    nui_line:append(num, M.highlights.json_number)
                    pos = pos + #num - 1
                end
            -- Handle boolean and null
            elseif line:match("^true", pos) then
                nui_line:append("true", M.highlights.json_boolean)
                pos = pos + 3
            elseif line:match("^false", pos) then
                nui_line:append("false", M.highlights.json_boolean)
                pos = pos + 4
            elseif line:match("^null", pos) then
                nui_line:append("null", M.highlights.json_null)
                pos = pos + 3
            -- Handle whitespace
            elseif char:match("%s") then
                nui_line:append(char)
            end
            pos = pos + 1
        end

        table.insert(lines, M.pad_line(nui_line))
    end

    return lines
end

return M
