local log = require("mcphub.utils.log")
-- Native listing server providing file buffer and mark listing tools

local function list_files(req, res)
    -- Now using req.params instead of req.arguments
    local path = req.params.path or vim.fn.getcwd()
    local pattern = req.params.pattern or "*"
    local include_hidden = req.params.include_hidden or false

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
    res:text(table.concat(files, "\n")):send()
end

-- Resource handlers
local function file_content_handler(req, res)
    local bufnr = vim.api.nvim_get_current_buf()
    local content = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
    -- Using simpler interface - uri is stored in response object
    return res:text(content):send()
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
                uriTemplate = "buffer://{bufnr}",
                mimeType = "text/plain",
                handler = function(req, res)
                    -- Use req.params.bufnr directly from template
                    local bufnr = tonumber(req.params.bufnr)
                    if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
                        return res:error("Invalid buffer number")
                    end

                    local content = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
                    return res:text(content):send()
                end,
            },
            {
                name = "File Content",
                description = "Get content of a file by path",
                uriTemplate = "file://{path}",
                mimeType = "text/plain",
                handler = function(req, res)
                    -- Use req.params.path directly from template
                    local file = io.open(req.params.path, "r")
                    if not file then
                        return res:error("Could not open file")
                    end

                    local content = file:read("*a")
                    file:close()

                    return res:text(content):send()
                end,
            },
        },
    },
}
