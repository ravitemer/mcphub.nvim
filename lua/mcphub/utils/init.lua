local NuiLine = require("mcphub.utils.nuiline")
local State = require("mcphub.state")
local Text = require("mcphub.utils.text")
local config = require("mcphub.config")
local ui_utils = require("mcphub.utils.ui")
local validation = require("mcphub.utils.validation")

local M = {}

--- Clean command arguments by filtering out empty strings and nil values.
--- This is particularly useful when handling command arguments that may contain optional values.
--- @param args table Array of command arguments
--- @return table Cleaned array with only valid arguments
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

local _is_jq_available
local function is_jq_available()
    if _is_jq_available ~= nil then
        return _is_jq_available
    end
    _is_jq_available = vim.fn.executable("jq") == 1
    return _is_jq_available
end

--- Pretty print JSON string with optional unescaping of forward slashes
---@param str string JSON string to format
---@param opts? { unescape_slashes?: boolean, use_jq?: boolean, sort_keys?: boolean } Optional options
---@return string Formatted JSON string
function M.pretty_json(str, opts)
    opts = opts or {}

    if opts.use_jq and is_jq_available() then
        local jq_cmd = { "jq" }
        if opts.sort_keys ~= false then
            vim.list_extend(jq_cmd, { "--sort-keys", "." })
        end
        local formatted = vim.fn.system(jq_cmd, str)
        if vim.v.shell_error ~= 0 or not formatted or formatted == "" then
            return M.format_json_string(str, opts.unescape_slashes)
        end
        if opts.unescape_slashes == nil or opts.unescape_slashes then
            formatted = formatted:gsub("\\/", "/")
        end
        return formatted
    else
        -- Fallback to custom implementation
        local ok, parsed = M.json_decode(str)
        if not ok then
            vim.notify("Failed to parse JSON string", vim.log.levels.INFO)
            return M.format_json_string(str, opts.unescape_slashes)
        end
        local sorted = opts.sort_keys ~= false and sort_keys_recursive(parsed) or parsed
        local encoded = vim.json.encode(sorted)
        return M.format_json_string(encoded, opts.unescape_slashes)
    end
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

---@param config MCPHub.Config
---@return { cmd: string, cmdArgs: string[] }
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

---@class ConfigParseResult
---@field ok boolean
---@field error string|nil
---@field name string|nil
---@field config table|nil

---@param text string
---@return ConfigParseResult
function M.parse_config_from_json(text)
    local result = {
        ok = false,
        error = nil,
        name = nil,
        config = nil,
    }

    local ok, parsed = M.json_decode(text)
    if not ok then
        result.error = "Invalid JSON format"
        return result
    end

    -- Case 1: Full mcpServers object
    if parsed.mcpServers then
        local name, config = next(parsed.mcpServers)
        if not name then
            result.error = "No server config found in mcpServers"
            return result
        end
        result.ok = true
        result.name = name
        result.config = config
        return result
    end

    -- Case 2: Server config object
    if parsed.command or parsed.url then
        local is_string = parsed.command and type(parsed.command) == "string" or type(parsed.url) == "string"
        if is_string then
            result.ok = true
            result.name = "unnamed"
            result.config = parsed
            return result
        end
    end

    -- Case 3: Single server name:config pair
    if vim.tbl_count(parsed) == 1 then
        local name, config = next(parsed)
        result.ok = true
        result.name = name
        result.config = config
        return result
    end

    result.error = "JSON should have a mcpServers key or name:config pair"
    return result
end

---@param opts { title: string?, placeholder: string?, old_server_name: string?, start_insert: boolean?, is_native: boolean?, on_success: function?, on_error: function?, go_to_placeholder: boolean?, virtual_lines: Array[]?, config_source: string?, ask_for_source: boolean? }
function M.open_server_editor(opts)
    opts = opts or {}
    ui_utils.multiline_input(opts.title or "Paste server's JSON config", opts.placeholder or "", function(content)
        if not content or vim.trim(content) == "" then
            if opts.on_error then
                opts.on_error("No content provided")
            end
            return
        end
        local result = M.parse_config_from_json(content)
        if result.ok then
            if opts.old_server_name and opts.old_server_name ~= "" then
                if result.name ~= opts.old_server_name then
                    if opts.is_native then
                        if opts.on_error then
                            opts.on_error("Server name cannot be changed for native servers")
                        else
                            vim.notify("Server name cannot be changed for native servers", vim.log.levels.ERROR)
                        end
                        return
                    end
                    -- If an old server name is provided, remove the old config
                    State.hub_instance:remove_server_config(opts.old_server_name)
                    vim.notify("Server " .. opts.old_server_name .. " removed", vim.log.levels.INFO)
                end
            end

            local function save(config_source)
                local success = State.hub_instance:update_server_config(
                    result.name,
                    result.config,
                    { merge = false, config_source = config_source }
                )
                if success then
                    vim.notify("Server " .. result.name .. " added successfully", vim.log.levels.INFO)
                    if opts.on_success then
                        opts.on_success(result.name, result.config)
                    end
                else
                    local error_msg = "Failed to update server configuration"
                    if opts.on_error then
                        opts.on_error(error_msg)
                    else
                        vim.notify(error_msg, vim.log.levels.ERROR)
                    end
                end
            end
            local config_files = State.current_hub.config_files or {}
            if opts.ask_for_source and #config_files > 1 then
                vim.ui.select(config_files, {
                    prompt = "Select config path to save the server configuration",
                }, function(choice)
                    if choice then
                        save(choice)
                    else
                        if opts.on_error then
                            opts.on_error("No config source selected")
                        end
                        return
                    end
                end)
            else
                save(opts.config_source)
            end
        else
            if opts.on_error then
                opts.on_error(result.error)
            else
                vim.notify(result.error, vim.log.levels.ERROR)
            end
        end
    end, {
        filetype = "json",
        start_insert = opts.start_insert or false,
        show_footer = false,
        position = "center", -- Always use center positioning for server editor
        go_to_placeholder = opts.go_to_placeholder,
        virtual_lines = opts.virtual_lines,
        validate = function(content)
            local result = M.parse_config_from_json(content)
            if not result.ok then
                vim.notify(result.error, vim.log.levels.ERROR)
                return false
            end

            if opts.is_native then
                if type(result.config) ~= "table" then
                    vim.notify("Config must be a table", vim.log.levels.ERROR)
                    return false
                end
                -- Native servers only need basic config validation
                return true
            else
                local valid = validation.validate_server_config(result.name, result.config)
                if not valid.ok then
                    vim.notify(valid.error.message, vim.log.levels.ERROR)
                    return false
                end
            end
            return true
        end,
        on_cancel = function()
            if opts.on_error then
                opts.on_error("User cancelled")
            end
        end,
    })
end

--- Confirm and delete a server configuration with a detailed preview
--- @param server_name string The name of the server to delete
--- @param on_delete function? Callback function to call after deletion
function M.confirm_and_delete_server(server_name, on_delete)
    if not server_name or server_name == "" then
        vim.notify("Server name is required for deletion", vim.log.levels.ERROR)
        return
    end
    local async = require("plenary.async")
    async.run(function()
        local config_manager = require("mcphub.utils.config_manager")
        local server_config = config_manager.get_server_config(server_name, true) or {}
        -- Create confirmation message with highlights
        local message = {}

        -- Header line with highlights
        local header_line = NuiLine()
        header_line:append("Do you want to delete ", Text.highlights.muted)
        header_line:append("'" .. server_name .. "'", Text.highlights.error)
        header_line:append(" server?", Text.highlights.muted)
        table.insert(message, header_line)
        table.insert(message, "")

        -- Current configuration preview
        if server_config then
            vim.list_extend(message, Text.render_json(vim.json.encode(server_config)))
        else
            local no_config_line = NuiLine()
            no_config_line:append("No current configuration found.", Text.highlights.muted)
            table.insert(message, no_config_line)
        end

        -- Show confirmation dialog
        local confirmed, cancelled = ui_utils.confirm(message, {
            min_width = 70,
            max_width = 90,
        })

        if confirmed and not cancelled then
            -- Delete the server
            if State.hub_instance then
                local success = State.hub_instance:remove_server_config(server_name)
                if success then
                    vim.notify("Server '" .. server_name .. "' deleted successfully!", vim.log.levels.INFO)
                    if on_delete then
                        on_delete(server_name)
                    end
                else
                    vim.notify("Failed to delete server '" .. server_name .. "'", vim.log.levels.ERROR)
                end
            else
                vim.notify("MCP Hub not available", vim.log.levels.ERROR)
            end
        end
    end, function() end)
end

--- Convert ISO 8601 timestamp to relative time format (e.g., "23s", "1d", "1hr", "2m")
---@param iso_string string ISO 8601 timestamp string
---@return string Relative time string
function M.iso_to_relative_time(iso_string)
    if not iso_string or iso_string == "" then
        return "unknown"
    end

    -- Parse ISO string to Unix timestamp
    local pattern = "(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)"
    local year, month, day, hour, min, sec = iso_string:match(pattern)

    if not year then
        return "invalid"
    end

    -- Convert to Unix timestamp
    local timestamp = os.time({
        year = tonumber(year),
        month = tonumber(month),
        day = tonumber(day),
        hour = tonumber(hour),
        min = tonumber(min),
        sec = tonumber(sec),
    })

    -- Get current time
    local now = os.time()
    local diff = now - timestamp

    -- Handle future dates
    if diff < 0 then
        diff = math.abs(diff)
        local future_result = M._format_time_diff(diff)
        return "in " .. future_result
    end

    return M._format_time_diff(diff)
end

--- Convert ms to relative time format (e.g., "23s", "1d", "1hr", "2m")
--- @param ms number Time in milliseconds
--- @return string Relative time string
function M.ms_to_relative_time(ms)
    if type(ms) ~= "number" then
        ms = tonumber(ms)
    end
    if not ms or ms < 0 then
        return "unknown"
    end

    local seconds = math.floor(ms / 1000)
    return M._format_time_diff(seconds)
end

--- Internal helper to format time difference
---@param diff number Time difference in seconds
---@return string Formatted time string
function M._format_time_diff(diff)
    if diff < 60 then
        return string.format("%ds", diff)
    elseif diff < 3600 then -- Less than 1 hour
        return string.format("%dm", math.floor(diff / 60))
    elseif diff < 86400 then -- Less than 1 day
        return string.format("%dh", math.floor(diff / 3600))
    elseif diff < 2592000 then -- Less than 30 days
        return string.format("%dd", math.floor(diff / 86400))
    elseif diff < 31536000 then -- Less than 1 year
        return string.format("%dmo", math.floor(diff / 2592000))
    else
        return string.format("%dy", math.floor(diff / 31536000))
    end
end

--- Decode a JSON string into a Lua table
--- @param str string The JSON string to decode
--- @param opts? {use_custom_parser: boolean} Optional options
--- @return boolean The decoded Lua table, or nil if decoding fails
--- @return table|nil
function M.json_decode(str, opts)
    opts = opts or {}
    local ok, result

    -- Try decoding using vim.json.decode for all
    ok, result = pcall(vim.json.decode, str, { luanil = { object = true, array = true } })
    if ok then
        return ok, result
    end
    -- If decoding fails, check if we should use a custom parser
    if not ok and opts.use_custom_parser then
        -- Try custom parser first (lua-json5) e.g `require
        if type(config.json_decode) == "function" then
            ok, result = pcall(config.json_decode, str)
            if ok then
                return ok, result
            end
        end

        -- INFO: We can bundle a lightweight JSON5 parser using Node.js or rust but it needs a breaking change wrt the build step. Without build step, including the bundled script which is bundled in development might not go well with the users security concerns. So we will not include it for now and let the user provide a custom parser if needed.
        -- -- Fallback to bundled JSON5 parser
        -- local plugin_root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h:h:h")
        -- local json5_script = plugin_root .. "/scripts/bundled_json5.js"
        --
        -- local json5_result = vim.fn.system({ "node", json5_script }, str)
        --
        -- if vim.v.shell_error == 0 and json5_result and vim.trim(json5_result) ~= "" then
        --     -- Parse the clean JSON output from bundled JSON5 parser
        --     ok, result = pcall(vim.json.decode, json5_result, { luanil = { object = true, array = true } })
        --     if ok then
        --         return ok, result
        --     end
        -- end
    end
    return false, result
end
return M
