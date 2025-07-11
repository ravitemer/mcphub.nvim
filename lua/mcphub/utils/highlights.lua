--[[ MCPHub highlight utilities ]]
local M = {}
M.setup_called = false

-- Highlight group names
M.groups = {
    title = "MCPHubTitle",
    header = "MCPHubHeader",
    header_btn = "MCPHubHeaderBtn",
    header_btn_shortcut = "MCPHubHeaderBtnShortcut",
    header_shortcut = "MCPHubHeaderShortcut",
    keymap = "MCPHubKeymap",

    success = "MCPHubSuccess",
    success_italic = "MCPHubSuccessItalic",
    success_fill = "MCPHubSuccessFill",
    info = "MCPHubInfo",
    warn = "MCPHubWarning",
    warn_fill = "MCPHubWarnFill",
    warn_italic = "MCPHubWarnItalic",
    error = "MCPHubError",
    error_fill = "MCPHubErrorFill",
    muted = "MCPHubMuted",
    link = "MCPHubLink",

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
    -- Diff visualization highlights
    diff_add = "MCPHubDiffAdd", -- New content being added
    diff_change = "MCPHubDiffChange", -- New content being added
    diff_delete = "MCPHubDiffDelete", -- Content being removed
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
    local val = hl[attr] and string.format("#%06x", hl[attr])
    if not val then
        val = fallback
    end
    return val
end

-- Apply highlight groups
function M.apply_highlights()
    -- Get colors from current theme
    local normal_bg = get_color("Normal", "bg", "#1a1b26")
    local normal_fg = get_color("Normal", "fg", "#c0caf5")
    local float_bg = get_color("NormalFloat", "bg", normal_bg)
    local border_fg = get_color("FloatBorder", "fg", "#555555")
    local border_bg = get_color("FloatBorder", "bg", normal_bg)
    local comment_fg = get_color("Comment", "fg", "#808080")

    -- Get semantic colors
    local error_color = get_color("DiagnosticError", "fg", "#f44747")
    local warn_color = get_color("DiagnosticWarn", "fg", "#ff8800")
    local info_color = get_color("DiagnosticInfo", "fg", "#4fc1ff")
    local success_color = get_color("DiagnosticHint", "fg", "#89d185")
    local macro_color = get_color("Macro", "fg", "#98c379")

    -- Get UI colors
    local pmenu_sel_bg = get_color("PmenuSel", "bg", "#444444")
    local pmenu_sel_fg = get_color("PmenuSel", "fg", "#d4d4d4")
    local special_key = get_color("Special", "fg", "#ff966c")
    local title_color = get_color("Title", "fg", "#c792ea")

    local highlights = {
        -- Title and headers
        -- pink
        [M.groups.title] = "Title",

        -- Header buttons - these need custom styling for visibility
        [M.groups.header_btn] = {
            fg = normal_bg,
            bg = title_color,
            bold = true,
        },
        [M.groups.header_btn_shortcut] = {
            fg = normal_bg,
            bg = title_color,
            bold = true,
        },

        -- Header components - use existing UI highlights for consistency
        [M.groups.header] = {
            fg = title_color,
            bg = "NONE",
            bold = true,
        },
        [M.groups.header_shortcut] = {
            fg = title_color,
            bold = true,
        },

        -- Button highlights for confirmation dialogs
        [M.groups.button_active] = "Visual",
        [M.groups.button_inactive] = "CursorLine",
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
        [M.groups.warn] = {
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
            fg = success_color,
        },
        [M.groups.success_italic] = {
            bg = "NONE",
            fg = success_color,
            bold = true,
            italic = true,
        },
        [M.groups.success_fill] = {
            bg = success_color,
            fg = normal_bg,
            bold = true,
        },
        [M.groups.muted] = {
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
        [M.groups.json_property] = "@property",
        [M.groups.json_string] = "String",
        [M.groups.json_number] = "Number",
        [M.groups.json_boolean] = "Boolean",
        [M.groups.json_null] = "keyword",
        [M.groups.json_punctuation] = "Delimiter",

        -- Markdown highlights
        [M.groups.text] = {
            fg = normal_fg,
            bg = "NONE",
        },
        [M.groups.code] = "Special",
        [M.groups.heading] = "Title",

        -- Seamless border (matches float background)
        [M.groups.seamless_border] = "FloatBorder",

        -- Diff visualization highlights
        -- [M.groups.diff_add] = "DiffAdd",
        -- [M.groups.diff_change] = "DiffChange",
        -- [M.groups.diff_delete] = "DiffDelete",
        -- Add shaded background for diff highlights
        [M.groups.diff_add] = {
            bg = "#1a2b32",
            fg = "#1abc9c",
            bold = true,
        },
        [M.groups.diff_change] = "DiffChange",
        [M.groups.diff_delete] = {
            bg = "#2d202a",
            fg = "#db4b4b",
            italic = true,
        },
    }

    for group, link in pairs(highlights) do
        local hl = type(link) == "table" and link or { link = link }
        hl.default = true
        vim.api.nvim_set_hl(0, group, hl)
    end
end

function M.setup()
    if M.setup_called then
        return
    end
    M.setup_called = true
    M.apply_highlights()

    local group = vim.api.nvim_create_augroup("MCPHubHighlights", { clear = true })
    vim.api.nvim_create_autocmd("ColorScheme", {
        group = group,
        callback = M.apply_highlights,
        desc = "Update MCPHub highlights when colorscheme changes",
    })
    vim.api.nvim_create_autocmd("VimEnter", {
        group = group,
        callback = M.apply_highlights,
        desc = "Apply MCPHub highlights on VimEnter",
    })
end

return M
