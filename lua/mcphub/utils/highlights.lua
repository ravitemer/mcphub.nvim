--[[ MCPHub highlight utilities ]]
local M = {}

-- Highlight group names
M.groups = {
    title = "MCPHubTitle",
    header = "MCPHubHeader",
    header_btn = "MCPHubHeaderBtn",
    header_btn_shortcut = "MCPHubHeaderBtnShortcut",
    header_accent = "MCPHubHeaderAccent",
    header_shortcut = "MCPHubHeaderShortcut",
    keymap = "MCPHubKeymap",
    error = "MCPHubError",
    error_fill = "MCPHubErrorFill",
    warning = "MCPHubWarning",
    warn = "MCPHubWarning",
    warn_fill = "MCPHubWarnFill",
    warn_italic = "MCPHubWarnItalic",
    info = "MCPHubInfo",
    success = "MCPHubSuccess",
    success_italic = "MCPHubSuccessItalic",
    success_fill = "MCPHubSuccessFill",
    muted = "MCPHubMuted",
    window_normal = "MCPHubNormal",
    window_border = "MCPHubBorder",
    active_item = "MCPHubActiveItem",
    active_item_muted = "MCPHubActiveItemMuted",
    link = "MCPHubLink",
    bg_blend = "MCPHubBgBlend",
    -- Button highlights for confirmation dialogs
    button_active = "MCPHubButtonActive",
    button_inactive = "MCPHubButtonInactive",
    -- Seamless border (matches float background)
    seamless_border = "MCPHubSeamlessBorder",
    -- JSON syntax highlights
    json_property = "MCPHubJsonProperty",
    json_string = "MCPHubJsonString",
    json_number = "MCPHubJsonNumber",
    json_boolean = "MCPHubJsonBoolean",
    json_null = "MCPHubJsonNull",
    json_punctuation = "MCPHubJsonPunctuation",
    -- Markdown specific highlights
    text = "MCPHubText", -- Regular markdown text
    code = "MCPHubCode", -- Code blocks
    heading = "MCPHubHeading", -- Markdown headings
}

-- Get highlight attributes from a highlight group
local function get_hl_attrs(name)
    local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = name })
    if not ok or not hl then
        return {}
    end
    return hl
end

-- Get color from highlight group or fallback
local function get_color(group, attr, fallback)
    local hl = get_hl_attrs(group)
    return hl[attr] and string.format("#%06x", hl[attr]) or fallback
end

-- Setup highlight groups
function M.setup()
    -- Get colors from current theme
    local normal_bg = get_color("Normal", "bg", "#1a1b26")
    local normal_fg = get_color("Normal", "fg", "#c0caf5")
    local float_bg = get_color("NormalFloat", "bg", normal_bg)
    local border_color = get_color("FloatBorder", "fg", "#555555")
    local comment_fg = get_color("Comment", "fg", "#808080")

    -- Get semantic colors
    local error_color = get_color("DiagnosticError", "fg", "#f44747")
    local warn_color = get_color("DiagnosticWarn", "fg", "#ff8800")
    local info_color = get_color("DiagnosticInfo", "fg", "#4fc1ff")
    local hint_color = get_color("DiagnosticHint", "fg", "#89d185")

    -- Get UI colors
    local pmenu_sel_bg = get_color("PmenuSel", "bg", "#444444")
    local pmenu_sel_fg = get_color("PmenuSel", "fg", "#d4d4d4")
    local special_key = get_color("Special", "fg", "#ff966c")
    local title_color = get_color("Title", "fg", "#c792ea")

    local highlights = {
        -- Window elements
        [M.groups.window_normal] = {
            bg = float_bg,
            fg = normal_fg,
        },
        [M.groups.window_border] = {
            bg = "NONE",
            fg = border_color,
            special = border_color,
        },
        [M.groups.bg_blend] = {
            bg = float_bg,
            fg = float_bg,
        },

        -- Title and headers
        [M.groups.title] = {
            bg = "NONE",
            fg = title_color,
            bold = true,
        },
        [M.groups.header] = {
            bg = pmenu_sel_bg,
            fg = pmenu_sel_fg,
        },
        [M.groups.header_btn] = {
            fg = normal_bg,
            bg = title_color,
            bold = true,
        },
        [M.groups.header_accent] = {
            bg = pmenu_sel_bg,
            fg = title_color,
            bold = true,
        },
        [M.groups.header_btn_shortcut] = {
            bg = title_color,
            fg = normal_bg,
            bold = true,
        },
        [M.groups.header_shortcut] = {
            bg = pmenu_sel_bg,
            fg = special_key,
            bold = true,
        },

        -- Interactive elements
        [M.groups.active_item] = {
            fg = normal_bg,
            bg = hint_color,
            bold = true,
        },
        [M.groups.active_item_muted] = {
            bg = hint_color,
            fg = comment_fg,
            bold = true,
        },

        -- Status and messages
        [M.groups.error] = {
            bg = "NONE",
            fg = error_color,
        },
        [M.groups.error_fill] = {
            bg = error_color,
            fg = normal_bg,
            bold = true,
        },
        [M.groups.warning] = {
            bg = "NONE",
            fg = warn_color,
        },
        [M.groups.warn] = {
            bg = "NONE",
            fg = warn_color,
        },
        [M.groups.warn_italic] = {
            bg = "NONE",
            fg = warn_color,
            italic = true,
        },
        [M.groups.warn_fill] = {
            bg = warn_color,
            fg = normal_bg,
            bold = true,
        },
        [M.groups.info] = {
            bg = "NONE",
            fg = info_color,
        },
        [M.groups.success] = {
            bg = "NONE",
            fg = hint_color,
        },
        [M.groups.success_italic] = {
            bg = "NONE",
            fg = hint_color,
            bold = true,
            italic = true,
        },
        [M.groups.success_fill] = {
            bg = hint_color,
            fg = normal_bg,
            bold = true,
        },
        [M.groups.muted] = {
            bg = "NONE",
            fg = comment_fg,
        },
        [M.groups.keymap] = {
            fg = special_key,
            bold = true,
        },
        [M.groups.link] = {
            bg = "NONE",
            fg = info_color,
            underline = true,
        },
        -- JSON syntax highlights linked to built-in groups
        [M.groups.json_property] = {
            bg = "NONE",
            fg = get_color("@property", "fg", special_key),
            italic = true,
            bold = true,
        },
        [M.groups.json_string] = {
            bg = "NONE",
            fg = get_color("String", "fg", hint_color),
        },
        [M.groups.json_number] = {
            bg = "NONE",
            fg = get_color("Number", "fg", info_color),
        },
        [M.groups.json_boolean] = {
            bg = "NONE",
            fg = get_color("Boolean", "fg", special_key),
        },
        [M.groups.json_null] = {
            bg = "NONE",
            fg = get_color("Keyword", "fg", warn_color), -- null is often highlighted as a keyword
        },
        [M.groups.json_punctuation] = {
            bg = "NONE",
            fg = get_color("Delimiter", "fg", comment_fg),
        },
        -- Markdown highlights
        [M.groups.text] = {
            bg = "NONE",
            fg = normal_fg,
        },
        [M.groups.code] = {
            -- bg = pmenu_sel_bg,
            fg = info_color,
        },
        [M.groups.heading] = {
            bg = "NONE",
            fg = title_color,
            bold = true,
        },
        -- Button highlights for confirmation dialogs
        [M.groups.button_active] = {
            bg = hint_color,
            fg = normal_bg,
            bold = true,
        },
        [M.groups.button_inactive] = {
            bg = pmenu_sel_bg,
            fg = normal_fg,
        },
        -- Seamless border (matches float background)
        [M.groups.seamless_border] = {
            bg = float_bg,
            fg = float_bg,
            special = float_bg,
        },
    }

    -- Set highlights
    for name, val in pairs(highlights) do
        val.default = true
        vim.api.nvim_set_hl(0, name, val)
    end
end

-- Setup an autocmd to update highlights when colorscheme changes
function M.setup_auto_update()
    local group = vim.api.nvim_create_augroup("MCPHubHighlights", { clear = true })
    vim.api.nvim_create_autocmd("ColorScheme", {
        group = group,
        callback = M.setup,
        desc = "Update MCPHub highlights when colorscheme changes",
    })
end

return M
