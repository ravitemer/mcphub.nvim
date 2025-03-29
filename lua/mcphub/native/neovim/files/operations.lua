local Path = require("plenary.path")

-- Utility to safely get file info
local function get_file_info(path)
    local fullpath = vim.fn.expand(path)
    local stat = vim.loop.fs_stat(fullpath)
    if not stat then
        return nil, "File not found: " .. path
    end

    return {
        name = vim.fn.fnamemodify(fullpath, ":t"),
        path = fullpath,
        size = stat.size,
        type = stat.type,
        modified = stat.mtime.sec,
        permissions = stat.mode,
        is_readonly = not vim.loop.fs_access(fullpath, "W"),
    }
end

-- Basic file operations tools
local file_tools = {
    {
        name = "read_file",
        description = "Read contents of a file",
        inputSchema = {
            type = "object",
            properties = {
                path = {
                    type = "string",
                    description = "Path to the file to read",
                },
                start_line = {
                    type = "number",
                    description = "Start reading from this line (1-based index)",
                    default = 1,
                },
                end_line = {
                    type = "number",
                    description = "Read until this line (inclusive)",
                    default = -1,
                },
            },
            required = { "path" },
        },
        handler = function(req, res)
            local params = req.params
            local p = Path:new(params.path)

            if not p:exists() then
                return res:error("File not found: " .. params.path)
            end

            if params.start_line and params.end_line then
                local extracted = {}
                local current_line = 0

                for line in p:iter() do
                    current_line = current_line + 1
                    if
                        current_line >= params.start_line and (params.end_line == -1 or current_line <= params.end_line)
                    then
                        table.insert(extracted, string.format("%4d │ %s", current_line, line))
                    end
                    if params.end_line ~= -1 and current_line > params.end_line then
                        break
                    end
                end
                return res:text(table.concat(extracted, "\n")):send()
            else
                return res:text(p:read()):send()
            end
        end,
    },
    {
        name = "delete_item",
        description = "Delete a file or directory",
        inputSchema = {
            type = "object",
            properties = {
                path = {
                    type = "string",
                    description = "Path to delete",
                },
            },
            required = { "path" },
        },
        handler = function(req, res)
            local p = Path:new(req.params.path)
            if not p:exists() then
                return res:error("Path not found: " .. req.params.path)
            end
            p:rm()
            return res:text("Successfully deleted: " .. req.params.path):send()
        end,
    },
    {
        name = "move_item",
        description = "Move or rename a file/directory",
        inputSchema = {
            type = "object",
            properties = {
                path = {
                    type = "string",
                    description = "Source path",
                },
                new_path = {
                    type = "string",
                    description = "Destination path",
                },
            },
            required = { "path", "new_path" },
        },
        handler = function(req, res)
            local p = Path:new(req.params.path)
            if not p:exists() then
                return res:error("Source path not found: " .. req.params.path)
            end

            local new_p = Path:new(req.params.new_path)
            p:rename({ new_name = new_p.filename })
            return res:text(string.format("Moved %s to %s", req.params.path, req.params.new_path)):send()
        end,
    },
}

return file_tools
