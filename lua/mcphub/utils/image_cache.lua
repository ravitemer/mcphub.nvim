--[[ MCPHub image cache utilities ]]
local M = {}

-- Cache directory
M.cache_dir = vim.fn.stdpath("cache") .. "/mcphub/images"

--- Get unique filename based on content hash
---@param data string Base64 encoded image data
---@param mime_type string MIME type of the image
---@return string filename
local function get_unique_filename(data, mime_type)
    -- local hash = vim.fn.sha256(data)
    local time = os.time()
    local ext = mime_type:match("image/(%w+)") or "bin"
    return string.format("%s.%s", time, ext)
end
--- Save image to temp file and return file path
---@param data string Base64 encoded image data
---@param mime_type string MIME type of the image
---@return string|nil filepath Path to saved file
function M.save_image(data, mime_type)
    local filename = get_unique_filename(data, mime_type)
    local filepath = M.cache_dir .. "/" .. filename

    -- Open file with proper error handling
    local file, err = io.open(filepath, "wb")
    if not file then
        error(string.format("Failed to open file for writing: %s", err))
        return nil
    end

    local success, result = pcall(function()
        -- Try base64 decode if it looks like base64
        if type(data) == "string" and data:match("^[A-Za-z0-9+/]+=*$") then
            local ok, decoded = pcall(vim.base64.decode, data)
            if ok then
                file:write(decoded)
                return
            end
        end

        -- Handle binary/blob data
        if type(data) == "string" then
            file:write(data)
        else
            error("Unsupported data type: " .. type(data))
        end
    end)

    file:close()

    if not success then
        vim.fn.delete(filepath)
        error(string.format("Failed to write image data: %s", result))
        return nil
    end

    return filepath
end
--- Clean all cached images
function M.cleanup()
    -- Get all files in the cache directory
    local files = vim.fn.glob(M.cache_dir .. "/*", true, true)
    for _, file in ipairs(files) do
        vim.fn.delete(file)
    end
end

--- Initialize image cache
function M.setup()
    -- Create cache directory if it doesn't exist
    vim.fn.mkdir(M.cache_dir, "p")

    -- Setup cleanup on exit
    vim.api.nvim_create_autocmd("VimLeavePre", {
        group = vim.api.nvim_create_augroup("mcphub_image_cache", { clear = true }),
        callback = function()
            M.cleanup()
        end,
    })
end

return M
