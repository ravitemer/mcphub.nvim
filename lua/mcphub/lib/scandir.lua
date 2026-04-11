local uv = vim.uv or vim.loop

local M = {}

local function is_hidden(name)
    return name:sub(1, 1) == "."
end

local function scan_fallback(root, opts, results, depth)
    local handle = uv.fs_scandir(root)
    if not handle then
        return
    end

    while true do
        local name, kind = uv.fs_scandir_next(handle)
        if not name then
            break
        end

        if not opts.hidden and is_hidden(name) then
            goto continue
        end

        local full_path = vim.fs.joinpath(root, name)
        if kind == "directory" then
            if opts.add_dirs then
                table.insert(results, full_path)
            end
            if opts.depth == nil or depth < opts.depth then
                scan_fallback(full_path, opts, results, depth + 1)
            end
        else
            table.insert(results, full_path)
        end

        ::continue::
    end
end

local function scan_git(root, opts)
    local command = {
        "git",
        "-C",
        root,
        "ls-files",
        "--cached",
        "--others",
        "--exclude-standard",
    }
    local result = vim.system(command, { text = true }):wait()
    if result.code ~= 0 or not result.stdout or result.stdout == "" then
        return nil
    end

    local files = {}
    for _, line in ipairs(vim.split(result.stdout, "\n", { plain = true, trimempty = true })) do
        local basename = vim.fs.basename(line)
        if opts.hidden or not is_hidden(basename) then
            table.insert(files, vim.fs.joinpath(root, line))
        end
    end
    return files
end

---@param root string
---@param opts? {hidden?: boolean, depth?: integer, respect_gitignore?: boolean, add_dirs?: boolean}
---@return string[]
function M.scan_dir(root, opts)
    opts = vim.tbl_extend("force", {
        hidden = false,
        depth = nil,
        respect_gitignore = false,
        add_dirs = false,
    }, opts or {})

    root = vim.fs.normalize(vim.fn.expand(root))

    if opts.respect_gitignore and not opts.add_dirs then
        local git_files = scan_git(root, opts)
        if git_files then
            return git_files
        end
    end

    local results = {}
    scan_fallback(root, opts, results, 1)
    table.sort(results)
    return results
end

return M
