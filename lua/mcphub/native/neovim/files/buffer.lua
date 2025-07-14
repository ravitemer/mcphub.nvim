local utils = require("mcphub.utils")

local function get_buffer_lines(buf_info)
    local cursor_line = buf_info.cursor_pos[1]
    local ok, lines = pcall(vim.api.nvim_buf_get_lines, buf_info.bufnr, 0, -1, false)
    if not ok or not lines then
        return { "Failed to get buffer lines" }
    end

    local formatted = {}
    for i, line in ipairs(lines) do
        local prefix = i == cursor_line and ">" or " "
        -- Escape any format strings in the line content
        line = line:gsub("%%", "%%%%")
        table.insert(formatted, string.format("%s %4d │ %s", prefix, i, line))
    end
    return formatted
end

local function get_marks(buf_info)
    local marks = vim.fn.getmarklist(buf_info.bufnr)
    local result = {}
    for _, mark in ipairs(marks) do
        if mark.mark:match("[a-zA-Z]$") then
            local ok, line = pcall(vim.api.nvim_buf_get_lines, buf_info.bufnr, mark.pos[2] - 1, mark.pos[2], false)
            local context = ok and line[1] or ""
            if context then
                context = context:gsub("%%", "%%%%")
                table.insert(
                    result,
                    string.format("%s: line %d, col %d: %s", mark.mark:sub(-1), mark.pos[2], mark.pos[3], context)
                )
            end
        end
    end
    return result
end

local function get_qf_entries(buf_info)
    local qf_list = vim.fn.getqflist()
    local result = {}
    for _, item in ipairs(qf_list) do
        if item.bufnr == buf_info.bufnr then
            local ok, line = pcall(vim.api.nvim_buf_get_lines, buf_info.bufnr, item.lnum - 1, item.lnum, false)
            local content = ok and line[1] or ""
            if content then
                content = content:gsub("%%", "%%%%")
                table.insert(result, string.format("%4d │ %s\n     └─ %s", item.lnum, content, item.text))
            end
        end
    end
    return result
end

---@type MCPResource
return {
    name = "Buffer",
    description = "Get detailed information about the currently active buffer including content, cursor position, and buffer metadata",
    uri = "neovim://buffer",
    mimeType = "text/plain",
    handler = function(req, res)
        local buf_info = req.editor_info.last_active
        if not buf_info then
            return res:error("No active buffer found")
        end
        if buf_info.bufnr == 0 then
            return res:error("No valid buffer found")
        end

        local lines = get_buffer_lines(buf_info)
        local marks = get_marks(buf_info)
        local qf_entries = get_qf_entries(buf_info)

        local sep = string.rep("─", 80)

        local text = string.format(
            [[
## Buffer Information
Name: %s
Bufnr: %d
Lines: %d
Cursor: line %d

%s
## Buffer Content
%s%s%s
]],
            buf_info.filename,
            buf_info.bufnr,
            buf_info.line_count,
            buf_info.cursor_pos[1],
            sep,
            table.concat(lines, "\n"),
            #marks > 0 and string.format("\n\n%s\n# Marks\n%s", sep, table.concat(marks, "\n")) or "",
            #qf_entries > 0 and string.format("\n\n%s\n# Quickfix Entries\n%s", sep, table.concat(qf_entries, "\n"))
                or ""
        )

        return res:text(text):send()
    end,
}
