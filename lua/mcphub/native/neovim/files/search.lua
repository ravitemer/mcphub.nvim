local Path = require("plenary.path")
local Text = require("mcphub.utils.text")
local scan = require("plenary.scandir")

-- Get file info utility
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

local search_tools = {
    {
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
            -- local path = vim.fn.expand(params.path or ".")
            local path = Path:new(params.path or "."):absolute()
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
    },
    {
        name = "list_directory",
        description = "List files and directories in a path",
        inputSchema = {
            type = "object",
            properties = {
                path = {
                    type = "string",
                    description = "Directory path to list",
                    default = ".",
                },
            },
        },
        handler = function(req, res)
            local params = req.params
            -- local path = vim.fn.expand(params.path or ".")
            local path = Path:new(params.path or "."):absolute()
            local depth = nil
            local hidden = false
            local respect_gitignore = true
            local include_dirs = false
            local scan_opts = {
                hidden = hidden,
                depth = depth,
                respect_gitignore = respect_gitignore,
                add_dirs = include_dirs,
            }

            local results = scan.scan_dir(path, scan_opts)

            if #results == 0 then
                return res:text("No files found in: " .. path):send()
            end

            -- Get file info for each result
            local file_results = {}
            for _, file in ipairs(results) do
                local ok, info = pcall(get_file_info, file)
                if ok and info then
                    table.insert(file_results, info)
                end
            end

            -- Format results
            local text = string.format("%s Directory Listing: %s\n%s\n", Text.icons.folder, path, string.rep("-", 40))

            for _, info in ipairs(file_results) do
                local icon = info.type == "directory" and Text.icons.folder or Text.icons.file
                local relative_path = info.path:sub(#path + 2)
                text = text .. string.format("%s %s\n", icon, relative_path)
            end

            text = text .. string.format("\nFound %d items", #file_results)
            return res:text(text):send()
        end,
    },
}

return search_tools
