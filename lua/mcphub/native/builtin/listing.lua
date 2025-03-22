local log = require("mcphub.utils.log")
-- Native listing server providing file buffer and mark listing tools

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

-- Resource handlers
local function file_content_handler(uri, output_handler)
    local bufnr = vim.api.nvim_get_current_buf()
    local content = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")

    output_handler({
        result = {
            contents = {
                {
                    uri = "buffer://current",
                    text = content,
                    mimeType = "text/plain",
                },
            },
        },
    })
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
                handler = list_files,
            },
        },
        resources = {
            {
                name = "Current Buffer Content",
                description = "Get content of current buffer",
                uri = "buffer://current",
                mimeType = "text/plain",
                handler = file_content_handler,
            },
        },
        resourceTemplates = {
            {
                name = "Buffer Content By Number",
                description = "Get content of a specific buffer by number",
                uriTemplate = "buffer://%d+",
                mimeType = "text/plain",
                handler = function(uri, output_handler)
                    local bufnr = tonumber(uri:match("buffer://(%d+)"))
                    if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
                        error("Invalid buffer number")
                    end

                    local content = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
                    output_handler({
                        result = {
                            contents = {
                                {
                                    uri = uri,
                                    text = content,
                                    mimeType = "text/plain",
                                },
                            },
                        },
                    })
                end,
            },
            {
                name = "File Content",
                description = "Get content of a file by path",
                uriTemplate = "file://.*",
                mimeType = "text/plain",
                handler = function(uri, output_handler)
                    local path = uri:match("file://(.*)")

                    local file = io.open(path, "r")
                    if not file then
                        return nil, "Could not open file"
                    end

                    local content = file:read("*a")
                    file:close()

                    output_handler({
                        result = {
                            contents = {
                                {
                                    uri = uri,
                                    text = content,
                                    mimeType = "text/plain",
                                },
                            },
                        },
                    })
                end,
            },
        },
    },
}
