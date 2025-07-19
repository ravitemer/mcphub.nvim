local Error = require("mcphub.utils.errors")
local State = require("mcphub.state")
local log = require("mcphub.utils.log")
local validation = require("mcphub.utils.validation")

local M = {}

--- Find server by name in current active servers
--- @param server_name string
--- @param from_non_native? boolean Whether to search in non-native servers
--- @return table|nil server object with config_source field
local function find_server_by_name(server_name, from_non_native)
    -- Search in native servers
    if from_non_native ~= true then
        for _, server in ipairs(State.server_state.native_servers or {}) do
            if server.name == server_name then
                return vim.tbl_extend("force", server, { is_native = true })
            end
        end
    end
    -- Search in regular MCP servers
    for _, server in ipairs(State.server_state.servers or {}) do
        if server.name == server_name then
            return server
        end
    end
    return nil
end

--- Read and parse a config file
--- @param file_path string Path to the config file
--- @return table|nil config Parsed config or nil on error
--- @return string|nil error Error message if parsing failed
local function read_config_file(file_path)
    -- Check if file exists, create with default content if not
    local file = io.open(file_path, "r")
    if not file then
        -- Ensure parent directory exists
        local dir_path = vim.fn.fnamemodify(file_path, ":h")
        if vim.fn.isdirectory(dir_path) == 0 then
            vim.fn.mkdir(dir_path, "p")
        end

        local create_file = io.open(file_path, "w")
        if not create_file then
            return nil, "Failed to create config file: " .. file_path
        end

        -- Write default config
        local default_config = { mcpServers = vim.empty_dict() }
        create_file:write(vim.json.encode(default_config))
        create_file:close()

        -- Reopen for reading
        file = io.open(file_path, "r")
        if not file then
            return nil, "Failed to reopen created config file: " .. file_path
        end
    end

    -- Read and parse JSON
    local content = file:read("*a")
    file:close()

    local success, json = utils.json_decode(content, { use_custom_parser = true })
    if not success then
        local error_msg = [[Invalid JSON in config file: ]]
            .. file_path
            .. [[

If your config file uses JSON5 syntax (comments, trailing commas), please:
1. Install lua-json5: https://github.com/Joakker/lua-json5
2. Add to your mcphub setup: json_decode = require('json5').parse

Example:
  require('mcphub').setup({
    json_decode = require('json5').parse,
    -- other config...
  })

Parse error: ]]
            .. tostring(json)
        return nil, error_msg
    end

    return json, nil
end

--- Detect original format and normalize config
--- @param config table Raw config object
--- @param file_path string File path for logging
--- @return table normalized_config Config with mcpServers key
--- @return string original_servers_key Original key used ("servers" or "mcpServers")
--- @return string|nil error Error message if validation failed
local function normalize_config_format(config, file_path)
    -- Format detection
    local has_servers = config.servers and type(config.servers) == "table"
    local has_mcp_servers = config.mcpServers and type(config.mcpServers) == "table"
    local original_servers_key = "mcpServers" -- default

    if not has_servers and not has_mcp_servers then
        return nil, nil, "Config file must contain either 'servers' or 'mcpServers' object: " .. file_path
    end

    local normalized = vim.deepcopy(config)

    -- Determine original format and normalize
    if has_servers and not has_mcp_servers then
        -- Pure VS Code format
        original_servers_key = "servers"
        normalized.mcpServers = config.servers
        log.debug("ConfigManager: VS Code format detected in " .. file_path)
    elseif has_servers and has_mcp_servers then
        -- Both exist, prefer servers (VS Code format takes precedence)
        original_servers_key = "servers"
        normalized.mcpServers = config.servers
        log.debug("ConfigManager: Both 'servers' and 'mcpServers' found in " .. file_path .. ", using 'servers'")
    end
    return normalized, original_servers_key, nil
end

--- Validate all servers in a config
--- @param config table Config with mcpServers
--- @param file_path string File path for error reporting
--- @return boolean success True if all servers are valid
--- @return string|nil error Error message if validation failed
local function validate_servers_in_config(config, file_path)
    for server_name, server_config in pairs(config.mcpServers or {}) do
        local validation_result = validation.validate_server_config(server_name, server_config)
        if not validation_result.ok then
            return false,
                "Server validation failed for '"
                    .. server_name
                    .. "' in "
                    .. file_path
                    .. ": "
                    .. validation_result.error.message
        end
    end
    return true, nil
end

--- Write config back to file preserving original format
--- @param config table Config to write
--- @param file_path string Path to write to
--- @param original_servers_key string Original key format ("servers" or "mcpServers")
--- @return boolean success True if write succeeded
--- @return string|nil error Error message if write failed
local function write_config_file(config, file_path, original_servers_key)
    local output_config = vim.deepcopy(config)

    -- Convert back to original format if needed
    if original_servers_key == "servers" and output_config.mcpServers then
        output_config.servers = output_config.mcpServers
        output_config.mcpServers = nil
    end

    local utils = require("mcphub.utils")
    local json_str = utils.pretty_json(vim.json.encode(output_config), { use_jq = true })

    local file = io.open(file_path, "w")
    if not file then
        return false, "Failed to open config file for writing: " .. file_path
    end

    file:write(json_str)
    file:close()
    return true, nil
end

--- Read, parse, normalize and validate a config file - returns table with all info
--- @param file_path string Path to the config file
--- @return table result {ok: boolean, json: table?, content: string?, original_key: string?, error: string?}
local function validate_config_file(file_path)
    -- Read raw config
    local raw_config, read_error = read_config_file(file_path)
    if not raw_config then
        return {
            ok = false,
            error = read_error,
        }
    end

    -- Normalize format and detect original key
    local normalized_config, original_servers_key, normalize_error = normalize_config_format(raw_config, file_path)
    if not normalized_config then
        return {
            ok = false,
            error = normalize_error,
        }
    end

    -- Validate all servers
    local valid, validation_error = validate_servers_in_config(normalized_config, file_path)
    if not valid then
        return {
            ok = false,
            error = validation_error,
        }
    end

    return {
        ok = true,
        json = normalized_config,
        original_json = raw_config,
        original_key = original_servers_key,
    }
end

--- Load a single config file and cache it
--- @param file_path string Path to the config file
--- @return boolean success Whether the file was loaded successfully
--- @return string|nil error Error message if loading failed
function M.load_config(file_path)
    if not file_path or file_path == "" then
        log.warn("ConfigManager: Empty file path provided")
        return false, "Empty file path provided"
    end

    local file_result = validate_config_file(file_path)
    if not file_result.ok then
        log.error("ConfigManager: " .. file_result.error)
        return false, file_result.error
    end

    -- Cache the normalized config, ensuring empty objects stay as objects
    State.config_files_cache = State.config_files_cache or {}
    State.config_files_cache[file_path] = {
        mcpServers = file_result.json.mcpServers or vim.empty_dict(),
        nativeMCPServers = file_result.json.nativeMCPServers or vim.empty_dict(),
    }
    vim.schedule(function()
        State:notify_subscribers({ config_files_cache = true }, "ui")
    end)

    log.debug("ConfigManager: Loaded config file: " .. file_path .. " (format: " .. file_result.original_key .. ")")
    return true, nil
end

--- Get the config source for a server
--- @param server string|table Server name or server object
--- @return string|nil Config source path or nil if not found
function M.get_config_source(server)
    local server_obj

    if type(server) == "string" then
        -- Find server in active servers list
        server_obj = find_server_by_name(server)
        if not server_obj then
            log.debug("ConfigManager: Server not found: " .. server)
            return nil
        end
    else
        -- server is an object
        server_obj = server
    end
    return server_obj.config_source or State.config.config
end

--- Get server config by server name or server object
--- @param server string|table Server name or server object with config_source
--- @param from_non_native? boolean Whether to get from non-native servers
--- @return table|nil Server config or nil if not found
function M.get_server_config(server, from_non_native)
    local server_name, config_source, is_native

    if type(server) == "string" then
        -- Find server in active servers list to get config_source
        local server_obj = find_server_by_name(server, from_non_native)
        if not server_obj then
            log.debug("ConfigManager: Server not found: " .. server)
            return nil
        end
        server_name = server
        config_source = server_obj.config_source
        is_native = server_obj.is_native or false
    else
        -- server is an object
        server_name = server.name
        config_source = server.config_source
        is_native = server.is_native or false
    end

    if not config_source then
        log.warn("ConfigManager: No config_source for server: " .. server_name)
        return nil
    end

    -- Ensure config is loaded
    if not State.config_files_cache or not State.config_files_cache[config_source] then
        log.debug("ConfigManager: Config not cached, loading: " .. config_source)
        if not M.load_config(config_source) then
            return nil
        end
    end

    -- Get config from cache
    local file_config = State.config_files_cache[config_source]
    if is_native then
        return file_config.nativeMCPServers[server_name]
    else
        return file_config.mcpServers[server_name]
    end
end

--- Update server config in the correct source file
--- @param server string|table Server name or server object
--- @param config table | nil New config to merge/replace
--- @param options? { merge : boolean?, config_source: string?} Options
--- @return boolean success Whether the update was successful
function M.update_server_config(server, config, options)
    options = options or {}
    local merge = options.merge ~= false -- default to true

    local server_name, config_source, is_native

    if type(server) == "string" then
        -- Use {} so that we can add a new server
        local server_obj = find_server_by_name(server) or {}
        server_name = server
        -- For servers without config_source, or new servers use global config
        config_source = server_obj.config_source or State.config.config
        is_native = server_obj.is_native or false
    else
        server_name = server.name
        if not server_name then
            log.error("ConfigManager: Invalid server object provided, missing name")
            return false
        end
        config_source = server.config_source or State.config.config
        is_native = server.is_native or false
    end
    if options.config_source then
        config_source = options.config_source
    end
    if not config_source then
        log.error("ConfigManager: No config_source for server: " .. server_name)
        return false
    end

    -- Load current config file
    local file_result = validate_config_file(config_source)
    if not file_result.ok then
        log.error(
            "ConfigManager: Failed to load config file for update: " .. config_source .. " - " .. file_result.error
        )
        return false
    end

    local file_config = file_result.json
    local original_servers_key = file_result.original_key
    local server_section = is_native and "nativeMCPServers" or "mcpServers"

    -- Ensure section exists
    file_config[server_section] = file_config[server_section] or {}

    -- Update server config
    if merge and type(config) == "table" and file_config[server_section][server_name] then
        file_config[server_section][server_name] =
            vim.tbl_deep_extend("force", file_config[server_section][server_name], config)
    else
        file_config[server_section][server_name] = config
    end

    -- Write back to file preserving original format
    local write_success, write_error = write_config_file(file_config, config_source, original_servers_key)
    if not write_success then
        log.error("ConfigManager: " .. write_error)
        return false
    end

    -- Update cache
    State.config_files_cache = State.config_files_cache or {}
    State.config_files_cache[config_source] = {
        mcpServers = file_config.mcpServers or {},
        nativeMCPServers = file_config.nativeMCPServers or {},
    }
    State:notify_subscribers({
        config_files_cache = true,
    }, "ui")

    log.debug("ConfigManager: Updated server config: " .. server_name .. " in " .. config_source)
    return true
end

--- Refresh config cache from files in current hub context
--- Uses State.current_hub.config_files to know which files to reload
--- @param paths string[]|nil Array of file paths to refresh, if nil uses current hub context
--- @return boolean success Whether all files were refreshed successfully
--- @return string|nil error Error message if any file failed to refresh
function M.refresh_config(paths)
    if not paths and (not State.current_hub or not State.current_hub.config_files) then
        log.debug("ConfigManager: No current hub context for refresh")
        return false, "No current hub context for refresh"
    end

    State.config_files_cache = {} -- Clear cache
    paths = paths or State.current_hub.config_files

    for _, file_path in ipairs(paths) do
        local ok, error_msg = M.load_config(file_path)
        if not ok then
            return false, "Failed to load config file '" .. file_path .. "': " .. (error_msg or "unknown error")
        end
    end

    log.debug("ConfigManager: Refreshed " .. #paths .. " config files")
    return true, nil
end

--- Get all active config files from current hub context
--- @param reverse? boolean Whether to reverse the order of files
--- @return string[] Array of config file paths
function M.get_active_config_files(reverse)
    if not State.current_hub or not State.current_hub.config_files then
        return {}
    end
    local config_files = vim.deepcopy(State.current_hub.config_files)
    if reverse then
        return vim.fn.reverse(config_files)
    end
    return State.current_hub.config_files
end

--- Get the raw config content for a specific file (for UI display)
--- @param file_path string Path to the config file
--- @return table|nil config content or nil if not found/invalid
function M.get_file_config(file_path)
    -- Ensure file is loaded in cache
    if not State.config_files_cache or not State.config_files_cache[file_path] then
        if not M.load_config(file_path) then
            return nil
        end
    end

    return State.config_files_cache[file_path]
end

--- Get the full config file content as JSON string (for Config UI)
--- @param file_path string Path to the config file
--- @return table|nil JSON content or nil if not found
--- @return string|nil error Error message if loading failed
function M.get_file_content_json(file_path)
    local file_result = validate_config_file(file_path)
    if not file_result.ok then
        return nil, file_result.error
    end
    return file_result.original_json, nil
end

--- Initialize config cache with current hub context
--- Should be called when hub context changes
--- @return boolean success
function M.initialize()
    log.debug("ConfigManager: Initializing with current hub context")
    return M.refresh_config()
end

return M
