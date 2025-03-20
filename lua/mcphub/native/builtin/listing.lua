-- Native listing server providing file, buffer and mark listing tools

local function list_files(args, output_handler)
    local path = args.path or vim.fn.getcwd()
    local pattern = args.pattern or "*"
    local include_hidden = args.include_hidden or false

    -- Simulate async work with vim.schedule
    vim.schedule(function()
        local files = vim.fn.globpath(path, pattern, false, true)
        if not include_hidden then
            files = vim.tbl_filter(function(f)
                return not vim.fn.fnamemodify(f, ":t"):match("^%.")
            end, files)
        end

        -- Convert to relative paths if cwd
        if path == vim.fn.getcwd() then
            files = vim.tbl_map(function(f)
                return vim.fn.fnamemodify(f, ":.")
            end, files)
        end
        -- Call handler with results
        output_handler({
            result = { content = { { type = "text", text = table.concat(files, "\n") } }, isError = false },
        })
    end)
end

local function list_buffers(args)
    local include_unlisted = args.include_unlisted or false
    local bufs = vim.api.nvim_list_bufs()

    local buf_info = {}
    for _, buf in ipairs(bufs) do
        if include_unlisted or vim.fn.buflisted(buf) == 1 then
            local info = {
                name = vim.api.nvim_buf_get_name(buf),
                listed = vim.fn.buflisted(buf) == 1,
                modified = vim.api.nvim_buf_get_option(buf, "modified"),
                readonly = vim.api.nvim_buf_get_option(buf, "readonly"),
                filetype = vim.api.nvim_buf_get_option(buf, "filetype"),
            }
            table.insert(buf_info, info)
        end
    end

    return { buffers = buf_info }
end

local function list_marks(args)
    local scope = args.scope or "buffer" -- buffer, global, all
    local marks = {}

    local function add_mark(mark)
        local pos = vim.api.nvim_get_mark(mark, {})
        if pos[1] ~= 0 then -- Mark exists
            local info = {
                mark = mark,
                line = pos[1],
                col = pos[2],
                buffer = pos[3],
                file = vim.api.nvim_buf_get_name(pos[3]),
            }
            table.insert(marks, info)
        end
    end

    if scope == "buffer" or scope == "all" then
        for mark in string.gmatch("abcdefghijklmnopqrstuvwxyz", ".") do
            add_mark(mark)
        end
    end

    if scope == "global" or scope == "all" then
        for mark in string.gmatch("ABCDEFGHIJKLMNOPQRSTUVWXYZ", ".") do
            add_mark(mark)
        end
    end

    return { marks = marks }
end

return {
    name = "listing",
    displayName = "Listing Tools",
    capabilities = {
        tools = {
            {
                name = "list_files",
                description = "List files in directory",
                inputSchema = {
                    type = "object",
                    properties = {
                        path = {
                            type = "string",
                            description = "Directory path (default: cwd)",
                        },
                        pattern = {
                            type = "string",
                            description = "Glob pattern (default: *)",
                        },
                        include_hidden = {
                            type = "boolean",
                            description = "Include hidden files (default: false)",
                        },
                    },
                },
                callback = list_files,
            },
            {
                name = "list_buffers",
                description = "List Neovim buffers",
                inputSchema = {
                    type = "object",
                    properties = {
                        include_unlisted = {
                            type = "boolean",
                            description = "Include unlisted buffers (default: false)",
                        },
                    },
                },
                callback = list_buffers,
            },
            {
                name = "list_marks",
                description = "List buffer/global marks",
                inputSchema = {
                    type = "object",
                    properties = {
                        scope = {
                            type = "string",
                            enum = { "buffer", "global", "all" },
                            description = "Scope of marks to list (default: buffer)",
                        },
                    },
                },
                callback = list_marks,
            },
        },
    },
}
