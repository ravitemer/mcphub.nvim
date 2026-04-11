local Text = require("mcphub.utils.text")
local uv = vim.uv or vim.loop

local function scan_dir(root, results)
    local handle = uv.fs_scandir(root)
    if not handle then
        return
    end
    while true do
        local name, kind = uv.fs_scandir_next(handle)
        if not name then
            break
        end
        if name:sub(1, 1) ~= "." then
            local full_path = vim.fs.joinpath(root, name)
            if kind == "directory" then
                scan_dir(full_path, results)
            else
                table.insert(results, full_path)
            end
        end
    end
end

local function git_list_files(root)
    local result = vim.system({
        "git",
        "-C",
        root,
        "ls-files",
        "--cached",
        "--others",
        "--exclude-standard",
    }, { text = true }):wait()

    if result.code ~= 0 or not result.stdout or result.stdout == "" then
        return nil
    end

    local files = {}
    for _, line in ipairs(vim.split(result.stdout, "\n", { plain = true, trimempty = true })) do
        table.insert(files, vim.fs.joinpath(root, line))
    end
    return files
end

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

---@type MCPTool[]
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
            if not params.pattern or params.pattern == "" then
                return res:error("Pattern is required for file search")
            end
            -- local path = vim.fn.expand(params.path or ".")
            local path = vim.fs.normalize(vim.fn.expand(params.path or "."))
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
            local path = vim.fs.normalize(vim.fn.expand(params.path or "."))
            local results = git_list_files(path) or {}
            if #results == 0 then
                scan_dir(path, results)
            end

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
