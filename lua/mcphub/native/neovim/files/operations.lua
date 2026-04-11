local uv = vim.uv or vim.loop

local function read_file(path)
    local fd = assert(io.open(path, "r"))
    local content = fd:read("*a")
    fd:close()
    return content
end

local function iter_lines(path)
    local fd = assert(io.open(path, "r"))
    return function()
        local line = fd:read("*line")
        if line == nil then
            fd:close()
            return nil
        end
        return line
    end
end

local function path_exists(path)
    return uv.fs_stat(path) ~= nil
end

---Basic file operations tools
---@type MCPTool[]
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
            local file_path = vim.fs.normalize(vim.fn.expand(params.path))

            if not path_exists(file_path) then
                return res:error("File not found: " .. params.path)
            end
            if params.start_line and params.end_line then
                params.start_line = tonumber(params.start_line)
                params.end_line = tonumber(params.end_line)
                if not params.start_line or not params.end_line then
                    return res:error("`start_line` and `end_line` must be numbers")
                end
                local extracted = {}
                local current_line = 0

                for line in iter_lines(file_path) do
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
                return res:text(read_file(file_path)):send()
            end
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
            local source = vim.fs.normalize(vim.fn.expand(req.params.path))
            if not path_exists(source) then
                return res:error("Source path not found: " .. req.params.path)
            end

            local target = vim.fs.normalize(vim.fn.expand(req.params.new_path))
            local rename_result = vim.fn.rename(source, target)
            if rename_result ~= 0 then
                return res:error("Failed to move " .. req.params.path .. " to " .. req.params.new_path)
            end
            return res:text(string.format("Moved %s to %s", req.params.path, req.params.new_path)):send()
        end,
    },
    {
        name = "read_multiple_files",
        description = "Read contents of multiple files in parallel. Prefer this tool when you need to view contents of more than one file at once.",
        inputSchema = {
            type = "object",
            properties = {
                paths = {
                    type = "array",
                    items = {
                        type = "string",
                    },
                    description = "Array of file paths to read",
                    examples = {
                        "file1.txt",
                        "/home/path/to/file2.txt",
                    },
                },
            },
            required = { "paths" },
        },
        handler = function(req, res)
            local params = req.params
            local results = {}
            local errors = {}

            if not params.paths or not vim.islist(params.paths) then
                return res:error("`paths` must be an array of strings. Provided " .. vim.inspect(params.paths))
            end

            if #params.paths == 0 then
                return res:error("`paths` array cannot be empty")
            end

            for i, path in ipairs(params.paths) do
                local file_path = vim.fs.normalize(vim.fn.expand(path))

                if not path_exists(file_path) then
                    table.insert(errors, string.format("File %d not found: %s", i, path))
                else
                    local success, content = pcall(function()
                        return read_file(file_path)
                    end)

                    if success then
                        table.insert(results, {
                            path = path,
                            content = content,
                            index = i,
                        })
                    else
                        table.insert(errors, string.format("Failed to read file %d (%s): %s", i, path, content))
                    end
                end
            end

            -- Format the response
            local response_parts = {}

            if #results > 0 then
                local file_word = #results == 1 and "file" or "files"
                table.insert(response_parts, string.format("Successfully read %d %s:\n", #results, file_word))

                for _, result in ipairs(results) do
                    table.insert(response_parts, string.format("=== File %d: %s ===", result.index, result.path))
                    table.insert(response_parts, result.content)
                    table.insert(response_parts, "") -- Empty line separator
                end
            end

            if #errors > 0 then
                if #results > 0 then
                    table.insert(response_parts, "\nErrors encountered:")
                end
                for _, error in ipairs(errors) do
                    table.insert(response_parts, "ERROR: " .. error)
                end
            end

            if #results == 0 and #errors > 0 then
                return res:error(table.concat(errors, "\n"))
            end

            return res:text(table.concat(response_parts, "\n")):send()
        end,
    },
    {
        name = "delete_items",
        description = "Delete multiple files or directories",
        inputSchema = {
            type = "object",
            properties = {
                paths = {
                    type = "array",
                    items = {
                        type = "string",
                    },
                    description = "Array of paths to delete",
                },
            },
            required = { "paths" },
        },
        handler = function(req, res)
            local params = req.params
            local results = {}
            local errors = {}

            if not params.paths or not vim.islist(params.paths) then
                return res:error("paths must be an array of strings")
            end

            if #params.paths == 0 then
                return res:error("paths array cannot be empty")
            end

            for i, path in ipairs(params.paths) do
                local target = vim.fs.normalize(vim.fn.expand(path))

                if not path_exists(target) then
                    table.insert(errors, string.format("Path %d not found: %s", i, path))
                else
                    local success, err = pcall(function()
                        return vim.fn.delete(target, "rf")
                    end)

                    if success and err == 0 then
                        table.insert(results, {
                            path = path,
                            index = i,
                        })
                    else
                        table.insert(errors, string.format("Failed to delete path %d (%s): %s", i, path, err))
                    end
                end
            end

            -- Format the response
            local response_parts = {}

            if #results > 0 then
                local item_word = #results == 1 and "item" or "items"
                table.insert(response_parts, string.format("Successfully deleted %d %s:", #results, item_word))

                for _, result in ipairs(results) do
                    table.insert(response_parts, string.format("  %d. %s", result.index, result.path))
                end
            end

            if #errors > 0 then
                if #results > 0 then
                    table.insert(response_parts, "\nErrors encountered:")
                end
                for _, error in ipairs(errors) do
                    table.insert(response_parts, "ERROR: " .. error)
                end
            end

            if #results == 0 and #errors > 0 then
                return res:error(table.concat(errors, "\n"))
            end

            return res:text(table.concat(response_parts, "\n")):send()
        end,
    },
}

return file_tools
