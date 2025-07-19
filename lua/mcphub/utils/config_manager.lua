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

--- Load a single config file and cache it
--- @param file_path string Path to the config file
--- @return boolean success Whether the file was loaded successfully
function M.load_config(file_path)
    log.stack("ConfigManager: load_config")
    if not file_path or file_path == "" then
        log.warn("ConfigManager: Empty file path provided")
        return false
    end

    local file_result = validation.validate_config_file(file_path)
    if not file_result.ok then
        log.error(
            "ConfigManager: Failed to load config file: "
                .. file_path
                .. " - "
                .. (file_result.error and file_result.error.message or "Unknown error")
        )
        return false
    end

    -- Cache the config, ensuring empty objects stay as objects
    State.config_files_cache = State.config_files_cache or {}
    State.config_files_cache[file_path] = {
        mcpServers = file_result.json.mcpServers or vim.empty_dict(),
        nativeMCPServers = file_result.json.nativeMCPServers or vim.empty_dict(),
    }
    vim.schedule(function()
        State:notify_subscribers({ config_files_cache = true }, "ui")
    end)

    log.debug("ConfigManager: Loaded config file: " .. file_path)
    return true
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
    local file_result = validation.validate_config_file(config_source)
    if not file_result.ok then
        log.error("ConfigManager: Failed to load config file for update: " .. config_source)
        return false
    end

    local file_config = file_result.json or {}
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

    -- Write back to file
    local utils = require("mcphub.utils")
    local json_str = utils.pretty_json(vim.json.encode(file_config), { use_jq = true })
    local file = io.open(config_source, "w")
    if not file then
        log.error("ConfigManager: Failed to open config file for writing: " .. config_source)
        return false
    end

    file:write(json_str)
    file:close()

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
function M.refresh_config(paths)
    if not paths and (not State.current_hub or not State.current_hub.config_files) then
        log.debug("ConfigManager: No current hub context for refresh")
        return false
    end

    local success = true
    State.config_files_cache = {} -- Clear cache
    paths = paths or State.current_hub.config_files

    for _, file_path in ipairs(paths) do
        if not M.load_config(file_path) then
            success = false
        end
    end

    log.debug("ConfigManager: Refreshed " .. #paths .. " config files")
    return success
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
--- @return string|nil JSON content or nil if not found
function M.get_file_content_json(file_path)
    local file_result = validation.validate_config_file(file_path)
    if not file_result.ok then
        return nil
    end

    return file_result.content
end

--- Initialize config cache with current hub context
--- Should be called when hub context changes
--- @return boolean success
function M.initialize()
    log.debug("ConfigManager: Initializing with current hub context")
    return M.refresh_config()
end

return M
