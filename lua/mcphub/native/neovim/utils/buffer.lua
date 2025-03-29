local M = {}

function M.get_directory_info(path)
    path = path or vim.loop.cwd()
    -- Check if git repo
    local is_git = vim.fn.system("git rev-parse --is-inside-work-tree 2>/dev/null"):match("true")
    local files = {}

    if is_git then
        -- Use git ls-files for git-aware listing
        local git_files = vim.fn.systemlist("git ls-files --cached --others --exclude-standard")
        for _, file in ipairs(git_files) do
            local stat = vim.loop.fs_stat(file)
            if stat then
                table.insert(files, {
                    name = file,
                    type = stat.type,
                    size = stat.size,
                    modified = stat.mtime.sec,
                })
            end
        end
    else
        -- Fallback to regular directory listing
        local handle = vim.loop.fs_scandir(path)
        if handle then
            while true do
                local name, type = vim.loop.fs_scandir_next(handle)
                if not name then
                    break
                end

                local stat = vim.loop.fs_stat(name)
                if stat then
                    table.insert(files, {
                        name = name,
                        type = type or stat.type,
                        size = stat.size,
                        modified = stat.mtime.sec,
                    })
                end
            end
        end
    end

    return {
        path = path,
        is_git = is_git,
        files = files,
    }
end
---@class BufferInfo
---@field name string
---@field is_visible boolean
---@field is_modified boolean
---@field is_loaded boolean
---@field lastused number
---@field bufnr number

---@class EditorInfo
---@field last_active BufferInfo
---@field buffers BufferInfo[]

---@return EditorInfo

function M.get_editor_info()
    local buffers = vim.fn.getbufinfo({ buflisted = 1 })
    local valid_buffers = {}
    local last_active = nil
    local max_lastused = 0

    for _, buf in ipairs(buffers) do
        -- Only include valid files (non-empty name and empty buftype)
        local buftype = vim.api.nvim_buf_get_option(buf.bufnr, "buftype")
        if buf.name ~= "" and buftype == "" then
            local buffer_info = {
                bufnr = buf.bufnr,
                name = buf.name,
                filename = buf.name,
                is_visible = #buf.windows > 0,
                is_modified = buf.changed == 1,
                is_loaded = buf.loaded == 1,
                lastused = buf.lastused,
                windows = buf.windows,
                winnr = buf.windows[1], -- Primary window showing this buffer
            }

            -- Add cursor info for currently visible buffers
            if buffer_info.is_visible then
                local win = buffer_info.winnr
                local cursor = vim.api.nvim_win_get_cursor(win)
                buffer_info.cursor_pos = cursor
            end

            -- Add additional buffer info
            buffer_info.filetype = vim.api.nvim_buf_get_option(buf.bufnr, "filetype")
            buffer_info.line_count = vim.api.nvim_buf_line_count(buf.bufnr)

            table.insert(valid_buffers, buffer_info)

            -- Track the most recently used buffer
            if buf.lastused > max_lastused then
                max_lastused = buf.lastused
                last_active = buffer_info
            end
        end
    end

    -- If no valid buffers found, provide default last_active
    if not last_active and #valid_buffers > 0 then
        last_active = valid_buffers[1]
    end

    return {
        last_active = last_active,
        buffers = valid_buffers,
    }
end
return M
