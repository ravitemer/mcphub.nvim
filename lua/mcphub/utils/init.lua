local log = require("mcphub.utils.log")

local M = {}

--- Clean command arguments by filtering out empty strings and nil values.
--- This is particularly useful when handling command arguments that may contain optional values.
---
--- @param args table Array of command arguments
--- @return table Cleaned array with only valid arguments
--- @example
--- -- Basic usage:
--- clean_args({"--port", "3000", nil, ""}) -- returns {"--port", "3000"}
---
--- -- With nested arrays (flattened):
--- clean_args({{"-f", "--flag"}, nil, {"value"}}) -- returns {"-f", "--flag", "value"}
function M.clean_args(args)
    return vim.iter(args or {})
        :flatten()
        :filter(function(arg)
            return arg ~= "" and arg ~= nil
        end)
        :totable()
end

local uid = 0
function M.gen_dump_path()
    uid = uid + 1
    local P = require("plenary.path")
    local path
    local id = string.gsub("xxxx4xxx", "[xy]", function(l)
        local v = (l == "x") and math.random(0, 0xf) or math.random(0, 0xb)
        return string.format("%x", v)
    end)
    if P.path.sep == "\\" then
        path = string.format("%s\\AppData\\Local\\Temp\\plenary_curl_%s.headers", os.getenv("USERPROFILE"), id)
    else
        local temp_dir = os.getenv("XDG_RUNTIME_DIR") or "/tmp"
        path = temp_dir .. "/plenary_curl_" .. id .. ".headers"
    end
    local nvim_pid = vim.uv.os_getpid()
    local dump_file = path .. nvim_pid .. uid
    return { "-D", dump_file .. ".headers" }
end

--- Format timestamp relative to now
---@param timestamp number Unix timestamp
---@return string
function M.format_relative_time(timestamp)
    local now = vim.loop.now()
    local diff = math.floor(now - timestamp)

    if diff < 1000 then -- Less than a second
        return "just now"
    elseif diff < 60000 then -- Less than a minute
        local seconds = math.floor(diff / 1000)
        return string.format("%ds", seconds)
    elseif diff < 3600000 then -- Less than an hour
        local minutes = math.floor(diff / 60000)
        local seconds = math.floor((diff % 60000) / 1000)
        return string.format("%dm %ds", minutes, seconds)
    elseif diff < 86400000 then -- Less than a day
        local hours = math.floor(diff / 3600000)
        local minutes = math.floor((diff % 3600000) / 60000)
        return string.format("%dh %dm", hours, minutes)
    else -- Days
        local days = math.floor(diff / 86400000)
        local hours = math.floor((diff % 86400000) / 3600000)
        return string.format("%dd %dh", days, hours)
    end
end

--- Format duration in seconds to human readable string
---@param seconds number Duration in seconds
---@return string Formatted duration
function M.format_uptime(seconds)
    if seconds < 60 then
        return string.format("%ds", seconds)
    elseif seconds < 3600 then
        return string.format("%dm %ds", math.floor(seconds / 60), seconds % 60)
    else
        local hours = math.floor(seconds / 3600)
        local mins = math.floor((seconds % 3600) / 60)
        return string.format("%dh %dm", hours, mins)
    end
end

--- Calculate the approximate number of tokens in a text string
--- This is a simple approximation using word count, which works reasonably well for most cases
---@param text string The text to count tokens from
---@return number approx_tokens The approximate number of tokens
function M.calculate_tokens(text)
    if not text or text == "" then
        return 0
    end

    -- Simple tokenization approximation (4 chars ≈ 1 token)
    local char_count = #text
    local approx_tokens = math.ceil(char_count / 4)

    -- Alternative method using word count
    -- local words = {}
    -- for word in text:gmatch("%S+") do
    --     table.insert(words, word)
    -- end
    -- local word_count = #words
    -- local approx_tokens = math.ceil(word_count * 1.3) -- Words + punctuation overhead

    return approx_tokens
end

--- Format token count for display
---@param count number The token count
---@return string formatted The formatted token count
function M.format_token_count(count)
    if count < 1000 then
        return tostring(count)
    elseif count < 1000000 then
        return string.format("%.1fk", count / 1000)
    else
        return string.format("%.1fM", count / 1000000)
    end
end

--- Fire an autocommand event with data
---@param name string The event name (without "User" prefix)
---@param data? table Optional data to pass to the event
function M.fire(name, data)
    vim.api.nvim_exec_autocmds("User", {
        pattern = name,
        data = data,
    })
end

--- Sort table keys recursively while preserving arrays
---@param tbl table The table to sort
---@return table sorted_tbl The sorted table
local function sort_keys_recursive(tbl)
    if type(tbl) ~= "table" then
        return tbl
    end

    -- Check if table is an array
    local is_array = true
    local max_index = 0
    for k, _ in pairs(tbl) do
        if type(k) ~= "number" then
            is_array = false
            break
        end
        max_index = math.max(max_index, k)
    end
    if is_array and max_index == #tbl then
        -- Process array values but preserve order
        local result = {}
        for i, v in ipairs(tbl) do
            result[i] = sort_keys_recursive(v)
        end
        return result
    end

    -- Sort object keys alphabetically (case-insensitive)
    local sorted = {}
    local keys = {}

    for k in pairs(tbl) do
        table.insert(keys, k)
    end
    table.sort(keys)
    for _, k in ipairs(keys) do
        sorted[k] = sort_keys_recursive(tbl[k])
    end
    return sorted
end

--- Pretty print JSON string with optional unescaping of forward slashes
---@param str string JSON string to format
---@param unescape_slashes boolean? Whether to unescape forward slashes (default: true)
---@return string Formatted JSON string
function M.pretty_json(str, unescape_slashes)
    -- Parse JSON string to table
    local ok, parsed = pcall(vim.json.decode, str)
    if not ok then
        vim.notify("Failed to parse JSON string", vim.log.levels.INFO)
        -- If parsing fails, return the original string formatted
        return M.format_json_string(str)
    end
    -- Sort keys recursively
    local sorted = sort_keys_recursive(parsed)
    -- encode doesn't preserve the order but keeps it at least kindof sorted
    local encoded = vim.json.encode(sorted)
    return M.format_json_string(encoded, unescape_slashes)
end

--- Format a JSON string with proper indentation
---@param str string JSON string to format
---@return string Formatted JSON string
function M.format_json_string(str, unescape_slashes)
    local level = 0
    local result = ""
    local in_quotes = false
    local escape_next = false
    local indent = "  "
    -- Default to true if not specified
    if unescape_slashes == nil then
        unescape_slashes = true
    end

    -- Pre-process to unescape forward slashes if requested
    if unescape_slashes then
        str = str:gsub("\\/", "/")
    end

    for i = 1, #str do
        local char = str:sub(i, i)

        -- Handle escape sequences properly
        if escape_next then
            escape_next = false
            result = result .. char
        elseif char == "\\" then
            escape_next = true
            result = result .. char
        elseif char == '"' then
            in_quotes = not in_quotes
            result = result .. char
        elseif not in_quotes then
            if char == "{" or char == "[" then
                level = level + 1
                result = result .. char .. "\n" .. string.rep(indent, level)
            elseif char == "}" or char == "]" then
                level = level - 1
                result = result .. "\n" .. string.rep(indent, level) .. char
            elseif char == "," then
                result = result .. char .. "\n" .. string.rep(indent, level)
            elseif char == ":" then
                -- Add space after colons for readability
                result = result .. ": "
            elseif char == " " or char == "\n" or char == "\t" then
            -- Skip whitespace in non-quoted sections
            -- (vim.json.encode already adds its own whitespace)
            else
                result = result .. char
            end
        else
            -- In quotes, preserve all characters
            result = result .. char
        end
    end
    return result
end

function M.is_windows()
    return vim.fn.has("win32") == 1 or vim.fn.has("win64") == 1
end

function M.get_default_cmds(config)
    local cmd, cmdArgs
    local bin_name = nil
    if config.use_bundled_binary then
        bin_name = M.get_bundled_mcp_path()
    else
        if M.is_windows() then
            bin_name = "mcp-hub.cmd"
        else
            bin_name = "mcp-hub"
        end
    end
    -- set default cmds
    if config.cmd == nil and config.cmdArgs == nil then
        if M.is_windows() then
            cmd = "cmd.exe"
            cmdArgs = {
                "/C",
                bin_name,
            }
        else
            cmd = bin_name
            cmdArgs = {}
        end
    else
        cmd = config.cmd or bin_name
        cmdArgs = config.cmdArgs or {}
    end
    return {
        cmd = cmd,
        cmdArgs = cmdArgs,
    }
end

--- Get path to bundled mcp-hub executable when build = "bundled_build.lua"
---@return string Path to mcp-hub executable in bundled directory
function M.get_bundled_mcp_path()
    local plugin_root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h:h:h")
    local base_path = plugin_root .. "/bundled/mcp-hub/node_modules/.bin/mcp-hub"
    if M.is_windows() then
        return base_path .. ".cmd"
    end
    return base_path
end

function M.safe_get(tbl, path)
    -- Handle nil input
    if tbl == nil then
        return nil
    end

    -- Split path by dots
    local parts = {}
    for part in path:gmatch("[^.]+") do
        parts[#parts + 1] = part
    end

    local current = tbl
    for _, key in ipairs(parts) do
        -- Convert string numbers to numeric indices
        if tonumber(key) then
            key = tonumber(key)
        end

        if type(current) ~= "table" then
            return nil
        end
        current = current[key]
        if current == nil then
            return nil
        end
    end

    return current
end

function M.parse_context(caller)
    local bufnr = nil
    local context = {}
    local type = caller.type
    local meta = caller.meta or {}
    if type == "codecompanion" then
        local is_within_variable = meta.is_within_variable == true
        local chat
        if is_within_variable then
            chat = M.safe_get(caller, "codecompanion.Chat") or M.safe_get(caller, "codecompanion.inline")
        else
            chat = M.safe_get(caller, "codecompanion.chat")
        end
        bufnr = M.safe_get(chat, "context.bufnr") or 0
    elseif type == "avante" then
        bufnr = M.safe_get(caller, "avante.code.bufnr") or 0
    elseif type == "hubui" then
        context = M.safe_get(caller, "hubui.context") or {}
    end
    return vim.tbl_extend("force", {
        bufnr = bufnr,
    }, context)
end

---@param mode string
---@return boolean
local function is_visual_mode(mode)
    return mode == "v" or mode == "V" or mode == "^V"
end

---Get the context of the current buffer.
---@param bufnr? integer
---@param args? table
---@return table
function M.get_buf_info(bufnr, args)
    bufnr = bufnr or vim.api.nvim_get_current_buf()

    -- Validate buffer
    if not vim.api.nvim_buf_is_valid(bufnr) then
        error("Invalid buffer number: " .. tostring(bufnr))
    end

    -- Find the window displaying this buffer
    local winnr
    for _, win in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_get_buf(win) == bufnr then
            winnr = win
            break
        end
    end

    -- Fallback to current window if buffer isn't displayed
    if not winnr then
        winnr = vim.api.nvim_get_current_win()
    end
    local mode = vim.fn.mode()
    local cursor_pos = { 1, 0 } -- Default to start of buffer

    -- Only get cursor position if we have a valid window
    if winnr and vim.api.nvim_win_is_valid(winnr) then
        local ok, pos = pcall(vim.api.nvim_win_get_cursor, winnr)
        if ok then
            cursor_pos = pos
        end
    end

    -- Get all buffer lines for context
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local start_line = cursor_pos[1]
    local start_col = cursor_pos[2]
    local end_line = cursor_pos[1]
    local end_col = cursor_pos[2]

    local is_visual = false
    local is_normal = true

    local function try_get_visual_selection()
        local ok, result = pcall(function()
            if args and args.range and args.range > 0 then
                is_visual = true
                is_normal = false
                mode = "v"
                return M.get_visual_selection(bufnr)
            elseif is_visual_mode(mode) then
                is_visual = true
                is_normal = false
                return M.get_visual_selection(bufnr)
            end
            return lines, start_line, start_col, end_line, end_col
        end)

        if not ok then
            -- Fallback to current cursor position on error
            vim.notify("Failed to get visual selection: " .. tostring(result), vim.log.levels.WARN)
            is_visual = false
            is_normal = true
            return lines, start_line, start_col, end_line, end_col
        end
        return result
    end

    lines, start_line, start_col, end_line, end_col = try_get_visual_selection()

    return {
        winnr = winnr,
        bufnr = bufnr,
        mode = mode,
        is_visual = is_visual,
        is_normal = is_normal,
        buftype = vim.api.nvim_buf_get_option(bufnr, "buftype") or "",
        filetype = vim.api.nvim_buf_get_option(bufnr, "filetype") or "",
        filename = vim.api.nvim_buf_get_name(bufnr),
        cursor_pos = cursor_pos,
        lines = lines,
        line_count = vim.api.nvim_buf_line_count(bufnr),
        start_line = start_line,
        start_col = start_col,
        end_line = end_line,
        end_col = end_col,
    }
end

return M
