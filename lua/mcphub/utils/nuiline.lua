---@diagnostic disable: undefined-doc-name, return-type-mismatch, undefined-field
--[[ Adapted from nui.line by Munif Tanjim
Source: https://github.com/MunifTanjim/nui.nvim/blob/main/lua/nui/line/init.lua
License: MIT ]]
local NuiText = require("mcphub.utils.nuitext")

---@class NuiLine
local Line = {}
Line.__index = Line

---@class NuiLine
---@field _texts NuiText[]

---@param texts? NuiText[]
function Line:init(texts)
    self._texts = texts or {}
end

---@param content string|NuiText|NuiLine
---@param highlight? string|nui_text_extmark highlight info
---@return NuiText|NuiLine
function Line:append(content, highlight)
    local block = content
    if block == nil then
        return self
    end
    if type(block) == "string" then
        block = NuiText(block, highlight)
    end
    if block._texts then
        ---@cast block NuiLine
        for _, text in ipairs(block._texts) do
            table.insert(self._texts, text)
        end
    else
        ---@cast block NuiText
        table.insert(self._texts, block)
    end
    return self
end

---@return string
function Line:content()
    return table.concat(vim.tbl_map(function(text)
        return text:content()
    end, self._texts))
end

---@return number
function Line:width()
    local width = 0
    for _, text in ipairs(self._texts) do
        width = width + text:width()
    end
    return width
end

---@param bufnr number buffer number
---@param ns_id number namespace id
---@param linenr number line number (1-indexed)
---@param char_start? number start character position (0-indexed)
function Line:highlight(bufnr, ns_id, linenr, char_start)
    local current_byte_start = char_start or 0
    for _, text in ipairs(self._texts) do
        text:highlight(bufnr, ns_id, linenr, current_byte_start)
        current_byte_start = current_byte_start + text:length()
    end
end

---@param bufnr number buffer number
---@param ns_id number namespace id
---@param linenr_start number start line number (1-indexed)
---@param linenr_end? number end line number (1-indexed)
function Line:render(bufnr, ns_id, linenr_start, linenr_end)
    local row_start = linenr_start - 1
    local row_end = linenr_end and linenr_end - 1 or row_start + 1
    local content = self:content()
    --handle newlines
    content = content:gsub("\n", "\\n")

    -- if vim.bo[bufnr].modifiable == false then
    --     vim.api.nvim_set_option_value("modifiable", true, { buf = bufnr })
    -- end
    -- Clear existing content
    vim.api.nvim_buf_set_lines(bufnr, row_start, row_end, false, { "" })
    -- Insert new content at column 0
    vim.api.nvim_buf_set_text(bufnr, row_start, 0, row_start, 0, { content })
    -- Highlight from column 0
    self:highlight(bufnr, ns_id, linenr_start, 0)
end

-- Create a new line instance
local function new_line(...)
    local instance = setmetatable({}, Line)
    instance:init(...)
    return instance
end

-- Static methods

---@param content string text content
---@param width number total width
---@param align? "left"|"center"|"right" text alignment
---@param highlight? string highlight group
---@return NuiLine
function Line.pad_text(content, width, align, highlight)
    local text_width = vim.api.nvim_strwidth(content)
    local padding = width - text_width

    if padding <= 0 then
        return new_line():append(content, highlight)
    end

    local line = new_line()
    local left_pad, right_pad = 0, 0

    if align == "right" then
        left_pad = padding
    elseif align == "center" then
        left_pad = math.floor(padding / 2)
        right_pad = padding - left_pad
    else -- left or default
        right_pad = padding
    end

    if left_pad > 0 then
        line:append(string.rep(" ", left_pad))
    end
    line:append(content, highlight)
    if right_pad > 0 then
        line:append(string.rep(" ", right_pad))
    end

    return line
end

---@param parts string[] text parts
---@param highlight? string highlight group
---@param separator? string separator between parts
---@return NuiLine
function Line.join(parts, highlight, separator)
    local line = new_line()
    separator = separator or " "

    for i, part in ipairs(parts) do
        if i > 1 then
            line:append(separator)
        end
        line:append(part, highlight)
    end

    return line
end

-- Create constructor
local NuiLine = setmetatable({
    pad_text = Line.pad_text, -- Export static methods
    join = Line.join,
}, {
    __call = function(_, ...)
        return new_line(...)
    end,
})

return NuiLine
