local Text = require("mcphub.utils.text")
local mcphub = require("mcphub")

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

-- Add file search tool
mcphub.add_tool("neovim", {
    name = "find_files",
    description = "Search for files by pattern",
    inputSchema = {
        type = "object",
        properties = {
            pattern = {
                type = "string",
                description = "Search pattern (e.g. *.lua)",
            },
            path = {
                type = "string",
                description = "Directory to search in",
                default = ".",
            },
            recursive = {
                type = "boolean",
                description = "Search recursively",
                default = true,
            },
        },
        required = { "pattern" },
    },
    handler = function(req, res)
        local params = req.params
        local path = vim.fn.expand(params.path or ".")
        local pattern = params.pattern

        -- Build glob pattern
        local glob = vim.fn.fnamemodify(path, ":p")
        if params.recursive then
            glob = glob .. "**/"
        end
        glob = glob .. pattern

        -- Find files
        local files = vim.fn.glob(glob, true, true)
        if #files == 0 then
            return res:text("No files found matching: " .. pattern):send()
        end

        -- Get file info
        local results = {}
        for _, file in ipairs(files) do
            local ok, info = pcall(get_file_info, file)
            if ok and info then
                table.insert(results, info)
            end
        end

        -- Format results
        local text = string.format("%s Search Results: %s\n%s\n", Text.icons.search, pattern, string.rep("-", 40))

        for _, info in ipairs(results) do
            local icon = info.type == "directory" and Text.icons.folder or Text.icons.file
            text = text .. string.format("%s %s\n", icon, info.path)
        end

        text = text .. string.format("\nFound %d matches", #results)
        return res:text(text):send()
    end,
})

mcphub.add_resource("neovim", {
    name = "Workspace Information",
    description = function()
        return "This resource gives comprehensive information about the workspace, editor and OS. Includes directory structure, visible and loaded buffers along with the OS information."
    end,
    uri = "neovim://workspace/info",
    mimeType = "text/plain",
    handler = function(req, res)
        -- res:text("Received message: " .. params.message):send()
        local os_utils = require("mcphub.native.neovim.utils.os")
        local buf_utils = require("mcphub.native.neovim.utils.buffer")
        local editor_info = buf_utils.get_editor_info()

        -- Get system information
        local os_info = os_utils.get_os_info()
        local dir_info = buf_utils.get_directory_info(vim.fn.getcwd())

        -- Format visible and loaded buffers
        local visible = vim.tbl_map(
            function(buf)
                return string.format("%s%s", buf.name, buf.bufnr == editor_info.last_active.bufnr and " (active)" or "")
            end,
            vim.tbl_filter(function(buf)
                return buf.is_visible
            end, editor_info.buffers)
        )

        local loaded = vim.tbl_map(
            function(buf)
                return string.format("%s%s", buf.name, buf.bufnr == editor_info.last_active.bufnr and " (active)" or "")
            end,
            vim.tbl_filter(function(buf)
                return (not buf.is_visible) and buf.is_loaded
            end, editor_info.buffers)
        )

        -- Format workspace files
        local workspace_files = vim.tbl_map(function(file)
            return string.format("%s (%s, %.2fKB)", file.name, file.type, file.size / 1024)
        end, dir_info.files)

        local text = string.format(
            [[
<environment_details>
# System Information
OS: %s (%s)
Hostname: %s
User: %s
Shell: %s
Memory: %.2f GB total, %.2f GB free

# Workspace
Current Directory: %s
Git Repository: %s
Files: %d

# Workspace Files
%s

# Neovim Visible Files
%s

# Neovim Loaded Files
%s

# Current Time
%s
</environment_details>
            ]],
            os_info.os_name,
            os_info.arch,
            os_info.hostname,
            os_info.env.user,
            os_info.env.shell,
            os_info.memory.total / (1024 * 1024 * 1024),
            os_info.memory.free / (1024 * 1024 * 1024),
            os_info.cwd,
            dir_info.is_git and "Yes" or "No",
            #dir_info.files,
            table.concat(workspace_files, "\n"),
            table.concat(visible, "\n"),
            table.concat(loaded, "\n"),
            os.date("%Y-%m-%d %H:%M:%S")
        )
        return res:text(text):send()
    end,
})
