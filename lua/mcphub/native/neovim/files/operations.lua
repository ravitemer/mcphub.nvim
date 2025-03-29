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
        name = "read",
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
        name = "write",
        description = "Write content to a file (opens diff for review)",
        inputSchema = {
            type = "object",
            properties = {
                path = {
                    type = "string",
                    description = "Path to the file to write",
                },
                contents = {
                    type = "string",
                    description = "Content to write to the file",
                },
            },
            required = { "path", "contents" },
        },
        handler = function(req, res)
            local p = Path:new(req.params.path)
            local path = p:absolute()

            -- Ensure parent directories exist
            p:touch({ parents = true })

            -- Get original content if file exists
            local original_content = ""
            if p:exists() then
                original_content = p:read()
            end

            -- Save current window and get target window
            local current_win = vim.api.nvim_get_current_win()
            local target_win = current_win

            if req.caller.type == "hubui" then
                req.caller.hubui:cleanup()
            end
            -- Try to use last active buffer's window if available
            if req.editor_info and req.editor_info.last_active then
                local last_active = req.editor_info.last_active
                if last_active.winnr and vim.api.nvim_win_is_valid(last_active.winnr) then
                    target_win = last_active.winnr
                end
            else
                --open the file using :edit command
                vim.cmd("edit " .. path)
                target_win = vim.api.nvim_get_current_win()
            end

            -- Create/get buffer for the file
            local bufnr = vim.fn.bufadd(path)
            vim.fn.bufload(bufnr)

            -- Show the buffer in the target window
            vim.api.nvim_win_set_buf(target_win, bufnr)

            -- Set buffer content to new content
            vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.split(req.params.contents, "\n"))

            -- Create diff view
            vim.cmd("vertical rightbelow split")
            local diff_bufnr = vim.api.nvim_create_buf(false, true)
            vim.api.nvim_win_set_buf(vim.api.nvim_get_current_win(), diff_bufnr)
            vim.api.nvim_buf_set_lines(diff_bufnr, 0, -1, false, vim.split(original_content, "\n"))
            vim.bo[diff_bufnr].buftype = "nofile"
            vim.bo[diff_bufnr].bufhidden = "wipe"
            vim.cmd("diffthis")
            vim.cmd("wincmd p") -- Go back to main window
            vim.cmd("diffthis")

            -- Set buffer as modified but don't save
            vim.bo[bufnr].modified = true

            -- Go back to original window
            vim.api.nvim_set_current_win(current_win)

            return res:text("File opened for review: " .. req.params.path):send()
        end,
    },
    {
        name = "delete",
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
        name = "move",
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
