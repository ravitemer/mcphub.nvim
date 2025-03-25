local Error = require("mcphub.errors")
local Job = require("plenary.job")
local State = require("mcphub.state")
local curl = require("plenary.curl")
local handlers = require("mcphub.utils.handlers")
local log = require("mcphub.utils.log")
local native = require("mcphub.native")
local prompt_utils = require("mcphub.utils.prompt")
local utils = require("mcphub.utils")
local validation = require("mcphub.validation")

-- Default timeouts
local QUICK_TIMEOUT = 1000 -- 1s for quick operations like health checks
local TOOL_TIMEOUT = 30000 -- 30s for tool calls
local RESOURCE_TIMEOUT = 30000 -- 30s for resource access

--- @class MCPHub
--- @field port number The port number for the MCP Hub server
--- @field config string Path to the MCP servers configuration file
--- @field cmd string The cmd to invoke the MCP Hub server
--- @field cmdArgs table The args to pass to the cmd to spawn the server
--- @field ready boolean Whether the connection to server is ready
--- @field server_job Job|nil The server process job if we started it
--- @field client_id string Unique identifier for this client
--- @field is_owner boolean Whether this instance started the server
--- @field is_shutting_down boolean Whether we're in the process of shutting down
local MCPHub = {}
MCPHub.__index = MCPHub

local function url_encode(str)
    if type(str) ~= "number" then
        str = str:gsub("\r?\n", "\r\n")
        str = str:gsub("([^%w%-%.%_%~ ])", function(c)
            return string.format("%%%02X", c:byte())
        end)
        str = str:gsub(" ", "+")
        return str
    else
        return str
    end
end
--- Create a new MCPHub instance
--- @param opts table Configuration options
--- @return MCPHub Instance of MCPHub
function MCPHub:new(opts)
    local self = setmetatable({}, MCPHub)

    -- Set up instance fields
    self.port = opts.port
    self.config = opts.config
    self.cmd = opts.cmd
    self.cmdArgs = opts.cmdArgs
    self.ready = false
    self.server_job = nil
    self.is_owner = false -- Whether we started the server
    self.is_shutting_down = false

    -- Generate unique client ID
    self.client_id = string.format("%s_%s_%s", vim.fn.getpid(), vim.fn.localtime(), vim.fn.rand())

    -- Update state
    State:update({
        server_state = {
            status = "disconnected",
            started_at = nil,
            pid = nil,
        },
    }, "server")

    return self
end

--- Start the MCP Hub server
--- @param opts? { on_ready: function, on_error: function }
function MCPHub:start(opts, restart_callback)
    opts = opts or State.config

    -- Update state
    State:update({
        server_state = {
            status = "connecting",
        },
    }, "server")
    local has_called_restart_callback = false

    -- Check if server is already running
    self:check_server(function(is_running)
        if is_running then
            log.debug("Server already running")
            self:handle_server_ready(opts)
            return
        end

        -- Start new server
        -- We're starting the server, mark as owner
        self.is_owner = true

        local node_bin = require("mcphub.utils").get_bundled_mcp_path()

        self.server_job = Job:new({
            command = self.cmd,
            args = utils.clean_args({ self.cmdArgs, "--port", tostring(self.port), "--config", self.config }),
            detached = true,
            on_stdout = vim.schedule_wrap(function(_, data)
                if has_called_restart_callback == false then
                    if restart_callback then
                        restart_callback(true)
                        has_called_restart_callback = true
                    end
                end
                handlers.ProcessHandlers.handle_output(data, self, opts)
            end),
            on_stderr = vim.schedule_wrap(function(_, data)
                handlers.ProcessHandlers.handle_output(data, self, opts)
            end),
            on_exit = vim.schedule_wrap(function(j, code)
                if code ~= 0 then
                    self:handle_server_error("Server process exited with code " .. (code or ""), opts)
                end
                State:update({
                    server_state = {
                        status = "disconnected",
                        pid = nil,
                    },
                }, "server")

                self.ready = false
                self.server_job = nil
            end),
        })

        self.server_job:start()
    end)
end

--- Handle server ready state
--- @param opts? { on_ready: function, on_error: function }
function MCPHub:handle_server_ready(opts)
    self.ready = true
    opts = opts or {}

    -- Update state
    State:update({
        server_state = {
            status = "connected",
            started_at = vim.loop.now(),
            pid = self.server_job and self.server_job.pid,
        },
    }, "server")

    -- update the state
    self:get_health({
        callback = function(response, err)
            if err then
                if self:is_ready() then
                    local health_err = Error("SERVER", Error.Types.SERVER.HEALTH_CHECK, "Health check failed", {
                        error = err,
                    })
                    State:add_error(health_err)
                end
            else
                State:update({
                    server_state = vim.tbl_extend("force", State.server_state, {
                        servers = response.servers or {},
                    }),
                }, "server")
                self:handle_servers_updated()

                -- Register client
                self:register_client({
                    callback = function(response, reg_err)
                        if reg_err then
                            local err = Error("SERVER", Error.Types.SERVER.CONNECTION, "Client registration failed", {
                                error = reg_err,
                            })
                            State:add_error(err)
                            if opts.on_error then
                                opts.on_error(tostring(err))
                            end
                            return
                        end

                        -- Fetch marketplace catalog after successful registration
                        self:get_marketplace_catalog()

                        if opts.on_ready then
                            opts.on_ready(self)
                        end
                    end,
                })
            end
        end,
    })
end

function MCPHub:handle_server_error(msg, opts)
    -- Create proper error object for server errors
    if not self.is_shutting_down then -- Prevent error logging during shutdown
        if opts.on_error then
            opts.on_error(tostring(err))
        end
    end
end

--- Check if server is running and handle connection
--- @param callback? function Optional callback(is_running: boolean)
--- @return boolean If no callback is provided, returns is_running
function MCPHub:check_server(callback)
    log.debug("Checking Server")
    if self:is_ready() then
        callback(true)
        return
    end

    -- Quick health check
    local opts = {
        timeout = QUICK_TIMEOUT,
        skip_ready_check = true,
    }

    opts.callback = function(response, err)
        if err then
            log.debug("Error while get health in check_server")
            callback(false)
        else
            local is_hub_server = response and response.server_id == "mcp-hub" and response.status == "ok"
            log.debug("Got health response in check_server, is_hub_server? " .. tostring(is_hub_server))
            callback(is_hub_server)
        end
    end

    self:get_health(opts)
end

--- Register client with server
--- @param opts? { callback?: function } Optional callback(response: table|nil, error?: string)
function MCPHub:register_client(opts)
    return self:api_request(
        "POST",
        "client/register",
        vim.tbl_extend("force", {
            body = {
                clientId = self.client_id,
            },
        }, opts or {})
    )
end

--- Get server status information
--- @param opts? { callback?: function } Optional callback(response: table|nil, error?: string)
--- @return table|nil, string|nil If no callback is provided, returns response and error
function MCPHub:get_health(opts)
    return self:api_request("GET", "health", opts)
end

--- Get server information if available
--- @param name string Server name
--- @param opts? { callback?: function } Optional callback(response: table|nil, error?: string)
--- @return table|nil, string|nil If no callback is provided, returns response and error
function MCPHub:get_server_info(name, opts)
    return self:api_request("GET", string.format("servers/%s/info", url_encode(name)), opts)
end

--- Start a disabled/disconnected MCP server
---@param name string Server name to start
---@param opts? { callback?: function } Optional callback(response: table|nil, error?: string)
---@return table|nil, string|nil If no callback is provided, returns response and error
function MCPHub:start_mcp_server(name, opts)
    opts = opts or {}
    local is_native = native.is_native_server(name)
    if is_native then
        local server = is_native
        server:start()
        State:notify_subscribers({
            server_state = true,
        }, "server")
    else
        -- First update state to show connecting
        if self:is_ready() then
            for i, server in ipairs(State.server_state.servers) do
                if server.name == name then
                    State.server_state.servers[i].status = "connecting"
                    break
                end
            end
            State:notify_subscribers({
                server_state = true,
            }, "server")
        end

        -- Call start endpoint
        self:api_request("POST", string.format("servers/%s/start", url_encode(name)), {
            callback = function(response, err)
                self:refresh()
                if opts.callback then
                    opts.callback(response, err)
                end
            end,
        })
    end
    self:update_server_config(name, {
        disabled = false,
    })
end

--- Stop an MCP server
---@param name string Server name to stop
---@param disable boolean Whether to disable the server
---@param opts? { callback?: function } Optional callback(response: table|nil, error?: string)
---@return table|nil, string|nil If no callback is provided, returns response and error
function MCPHub:stop_mcp_server(name, disable, opts)
    opts = opts or {}

    local is_native = native.is_native_server(name)
    if is_native then
        local server = is_native
        server:stop()
        State:notify_subscribers({
            server_state = true,
        }, "server")
    else
        -- First update state to show disconnecting
        if self:is_ready() then
            for i, server in ipairs(State.server_state.servers) do
                if server.name == name then
                    State.server_state.servers[i].status = "disconnecting"
                    break
                end
            end
            State:notify_subscribers({
                server_state = true,
            }, "server")
        end
        -- Call stop endpoint
        self:api_request("POST", string.format("servers/%s/stop", url_encode(name)), {
            query = disable and {
                disable = "true",
            } or nil,
            callback = function(response, err)
                self:refresh()
                if opts.callback then
                    opts.callback(response, err)
                end
            end,
        })
    end
    self:update_server_config(name, {
        disabled = disable or false,
    })
end

--- Call a tool on a server
--- @param server_name string
--- @param tool_name string
--- @param args table
--- @param opts? { callback?: function, timeout?: number } Optional callback(response: table|nil, error?: string) and timeout in ms (default 30s)
--- @return table|nil, string|nil If no callback is provided, returns response and error
function MCPHub:call_tool(server_name, tool_name, args, opts)
    opts = opts or {}
    if opts.callback then
        local original_callback = opts.callback
        opts.callback = function(response, err)
            if opts.parse_response == true then
                response = prompt_utils.parse_tool_response(response)
            end
            original_callback(response, err)
        end
    end
    local arguments = args or {}
    if vim.tbl_isempty(arguments) then
        --HACK: add a property that will force encoding as an object
        arguments.__object = true
    end

    -- Check native servers first
    local is_native = native.is_native_server(server_name)
    if is_native then
        local server = is_native
        local result, err = server:call_tool(tool_name, args, opts)
        if opts.callback == nil then
            return (opts.parse_response == true and prompt_utils.parse_tool_response(result) or result), err
        end
        return
    end

    local response, err = self:api_request(
        "POST",
        string.format("servers/%s/tools", url_encode(server_name)),
        vim.tbl_extend("force", {
            timeout = opts.timeout or TOOL_TIMEOUT,
            body = {
                tool = tool_name,
                arguments = arguments,
            },
        }, opts)
    )

    -- handle sync calls
    if opts.callback == nil then
        return (opts.parse_response == true and prompt_utils.parse_tool_response(response) or response), err
    end
end

--- Access a server resource
--- @param server_name string
--- @param uri string
--- @param opts? { callback?: function, timeout?: number } Optional callback(response: table|nil, error?: string) and timeout in ms (default 30s)
--- @return table|nil, string|nil If no callback is provided, returns response and error
function MCPHub:access_resource(server_name, uri, opts)
    opts = opts or {}
    if opts.callback then
        local original_callback = opts.callback
        opts.callback = function(response, err)
            if opts.parse_response == true then
                response = prompt_utils.parse_resource_response(response)
            end
            original_callback(response, err)
        end
    end

    -- Check native servers first
    local is_native = native.is_native_server(server_name)
    if is_native then
        local server = is_native
        local result, err = server:access_resource(uri, opts)
        if opts.callback == nil then
            return (opts.parse_response == true and prompt_utils.parse_resource_response(result) or result), err
        end
        return
    end

    -- Otherwise proxy to MCP server
    local response, err = self:api_request(
        "POST",
        string.format("servers/%s/resources", url_encode(server_name)),
        vim.tbl_extend("force", {
            timeout = opts.timeout or RESOURCE_TIMEOUT,
            body = {
                uri = uri,
            },
        }, opts)
    )
    -- handle sync calls
    if opts.callback == nil then
        return (opts.parse_response == true and prompt_utils.parse_resource_response(response) or response), err
    end
end

--- API request helper
--- @param method string HTTP method
--- @param path string API path
--- @param opts? { body?: table, timeout?: number, skip_ready_check?: boolean, callback?: function, query?: table }
--- @return table|nil, string|nil If no callback is provided, returns response and error
function MCPHub:api_request(method, path, opts)
    opts = opts or {}
    local callback = opts.callback

    -- Build URL with query parameters if any
    local url = string.format("http://localhost:%d/api/%s", self.port, path)
    if opts.query then
        local params = {}
        for k, v in pairs(opts.query) do
            table.insert(params, k .. "=" .. v)
        end
        url = url .. "?" .. table.concat(params, "&")
    end

    -- Prepare request options
    local request_opts = {
        url = url,
        method = method,
        timeout = opts.timeout or QUICK_TIMEOUT,
        headers = {
            ["Content-Type"] = "application/json",
            ["Accept"] = "application/json",
        },
        on_error = vim.schedule_wrap(function(err)
            log.debug(string.format("Error while making request to %s: %s", path, vim.inspect(err)))
            local error = handlers.ResponseHandlers.process_error(err)
            if not self:is_ready() and path == "health" then
                callback(nil, tostring(error))
            else
                State:add_error(error)
            end
        end),
    }
    if opts.body then
        request_opts.body = vim.fn.json_encode(opts.body)
    end

    -- Only skip ready check for health check
    if not opts.skip_ready_check and not self.ready and path ~= "health" then
        local err = Error("SERVER", Error.Types.SERVER.INVALID_STATE, "MCP Hub not ready")
        State:add_error(err)
        if callback then
            callback(nil, tostring(err))
            return
        else
            return nil, tostring(err)
        end
    end

    -- Process response
    local function process_response(response)
        local curl_error = handlers.ResponseHandlers.handle_curl_error(response, request_opts)
        if curl_error then
            State:add_error(curl_error)
            if callback then
                callback(nil, tostring(curl_error))
                return
            else
                return nil, tostring(curl_error)
            end
        end

        local http_error = handlers.ResponseHandlers.handle_http_error(response, request_opts)
        if http_error then
            State:add_error(http_error)
            if callback then
                callback(nil, tostring(http_error))
                return
            else
                return nil, tostring(http_error)
            end
        end

        local result, parse_error = handlers.ResponseHandlers.parse_json(response.body, request_opts)
        if parse_error then
            State:add_error(parse_error)
            if callback then
                callback(nil, tostring(parse_error))
                return
            else
                return nil, tostring(parse_error)
            end
        end

        if callback then
            callback(result)
        else
            return result
        end
    end

    if callback then
        -- Async mode
        curl.request(vim.tbl_extend("force", request_opts, {
            callback = vim.schedule_wrap(function(response)
                process_response(response)
            end),
        }))
    else
        -- Sync mode
        return process_response(curl.request(request_opts))
    end
end

--- Update server configuration in the MCP config file
---@param server_name string Name of the server to update
---@param updates table Key-value pairs to update in the server config (command, args, env, disabled)
---@return boolean, string|nil Returns success status and error message if any
--- Load and validate config file
---@private
function MCPHub:load_config()
    -- Validate and read current config
    local result = validation.validate_config_file(self.config)
    if not result.ok then
        return false, tostring(result.error)
    end

    return result
end

function MCPHub:handle_servers_updated()
    State:emit("servers_updated", { prompt = self:get_active_servers_prompt(), hub = self })
end

function MCPHub:handle_capability_updates(data)
    local server = data.server
    if not server then
        return
    end
    for _, s in ipairs(State.server_state.servers) do
        if s.name == server then
            if data.type == "TOOL" then
                s.capabilities.tools = data.tools or {}
                State:emit("tool_list_changed", { server = data.server, hub = self, tools = data.tools })
            elseif data.type == "RESOURCE" then
                s.capabilities.resources = data.resources or {}
                s.capabilities.resourceTemplates = data.resourceTemplates or {}
                State:emit("resource_list_changed", {
                    server = data.server,
                    hub = self,
                    resources = data.resources,
                    resourceTemplates = data.resourceTemplates,
                })
            end
            break
        end
    end
    State:notify_subscribers({
        server_state = true,
    }, "server")
end

--- Update server configuration in the MCP config file
---@param server_name string Name of the server to update
---@param updates table|nil Key-value pairs to update in the server config or nil to remove
---@param opts? { callback?: function } Optional callback(success: boolean)
---@return boolean, string|nil Returns success status and error message if any
function MCPHub:update_server_config(server_name, updates, opts)
    opts = opts or {}
    -- Load and validate current config
    local result = self:load_config()
    if not result.ok then
        return false, tostring(result.error)
    end

    local config = result.json
    -- Ensure mcpServers exists
    config.mcpServers = config.mcpServers or {}
    config.nativeMCPServers = config.nativeMCPServers or {}

    local is_native = native.is_native_server(server_name)
    local current_object = is_native and config.nativeMCPServers or config.mcpServers
    if updates then
        -- Update mode: merge updates with existing config
        current_object[server_name] = vim.tbl_deep_extend("force", current_object[server_name] or {}, updates)
    else
        -- Remove mode: delete server config
        current_object[server_name] = nil
    end

    -- Write updated config back to file
    local json_str = utils.pretty_json(vim.json.encode(config))
    local file = io.open(self.config, "w")
    if not file then
        return false, "Failed to open config file for writing"
    end

    file:write(json_str)
    file:close()

    -- Update State
    State:update({
        servers_config = config.mcpServers,
        native_servers_config = config.nativeMCPServers,
    }, "setup")

    return true
end

--- Remove server configuration
---@param mcpId string Server ID to remove
---@param opts? { callback?: function } Optional callback(success: boolean)
---@return boolean, string|nil Returns success status and error message if any
function MCPHub:remove_server_config(mcpId, opts)
    -- Use update_server_config with nil updates to remove
    return self:update_server_config(mcpId, nil, opts)
end

function MCPHub:stop()
    self.is_shutting_down = true

    -- Unregister client
    self:api_request("POST", "client/unregister", {
        body = {
            clientId = self.client_id,
        },
    })

    -- if self.is_owner then
    --     if self.server_job then
    --         self.server_job:shutdown()
    --     end
    -- end

    State:update({
        server_state = {
            status = "disconnected",
            pid = nil,
        },
    }, "server")

    -- Clear state
    self.ready = false
    self.is_owner = false
    self.is_shutting_down = false
    self.server_job = nil
end

function MCPHub:is_ready()
    return self.ready
end

function MCPHub:refresh()
    if not self:ensure_ready() then
        return
    end
    local response, err = self:get_health()
    if err then
        local health_err = Error("SERVER", Error.Types.SERVER.HEALTH_CHECK, "Refresh failed", {
            error = err,
        })
        State:add_error(health_err)
        return false
    else
        State:update({
            server_state = vim.tbl_extend("force", State.server_state, {
                servers = response.servers or {},
            }),
        }, "server")
        self:handle_servers_updated()
        return true
    end
end

function MCPHub:hard_refresh()
    if not self:ensure_ready() then
        return
    end
    local response, err = self:api_request("GET", "refresh")
    if err then
        local health_err = Error("SERVER", Error.Types.SERVER.HEALTH_CHECK, "Hard Refresh failed", {
            error = err,
        })
        State:add_error(health_err)
        return false
    else
        State:update({
            server_state = vim.tbl_extend("force", State.server_state, {
                servers = response.servers or {},
            }),
        }, "server")
        self:handle_servers_updated()
        return true
    end
end

function MCPHub:restart(callback)
    if not self:ensure_ready() then
        return
    end
    if self.is_owner then
        self:stop()
        State:reset()
        self:start(nil, callback)
    else
        vim.notify("Only the owner can restart the server", vim.log.levels.INFO)
        self:refresh()
        callback(true)
    end
end

function MCPHub:ensure_ready()
    if not self:is_ready() then
        log.error("Server not ready. Make sure you call display after ensuring the mcphub is ready.")
        return false
    end
    return true
end

--- Get servers with their tools filtered based on server config
---@return table[] Array of connected servers with disabled tools filtered out
function MCPHub:get_servers()
    if not self:is_ready() then
        return {}
    end
    local filtered_servers = {}

    -- Add regular MCP servers
    for _, server in ipairs(State.server_state.servers or {}) do
        if server.status == "connected" then
            local server_config = State.servers_config[server.name] or {}
            local disabled_tools = server_config.disabled_tools or {}

            -- Create a copy of the server with filtered tools
            local filtered_server = vim.deepcopy(server)
            if filtered_server.capabilities and filtered_server.capabilities.tools then
                -- Filter out disabled tools
                filtered_server.capabilities.tools = vim.tbl_filter(function(tool)
                    return not vim.tbl_contains(disabled_tools, tool.name)
                end, filtered_server.capabilities.tools)
            end
            table.insert(filtered_servers, filtered_server)
        end
    end

    -- Add native servers
    for _, server in ipairs(State.server_state.native_servers or {}) do
        if server.status == "connected" then
            local server_config = State.native_servers_config[server.name] or {}
            local disabled_tools = server_config.disabled_tools or {}

            -- Create a copy of the server with filtered tools
            local filtered_server = vim.deepcopy(server)
            if filtered_server.capabilities and filtered_server.capabilities.tools then
                -- Filter out disabled tools
                filtered_server.capabilities.tools = vim.tbl_filter(function(tool)
                    return not vim.tbl_contains(disabled_tools, tool.name)
                end, filtered_server.capabilities.tools)
            end
            table.insert(filtered_servers, filtered_server)
        end
    end

    return filtered_servers
end

function MCPHub:get_resources()
    local active_servers = self:get_servers()
    local resources = {}
    for _, server in ipairs(active_servers) do
        if server.capabilities and server.capabilities.resources then
            for _, resource in ipairs(server.capabilities.resources) do
                table.insert(
                    resources,
                    vim.tbl_extend("force", resource, {
                        server_name = server.name,
                    })
                )
            end
        end
    end
    return resources
end

function MCPHub:get_tools()
    local active_servers = self:get_servers()
    local tools = {}
    for _, server in ipairs(active_servers) do
        if server.capabilities and server.capabilities.tools then
            for _, tool in ipairs(server.capabilities.tools) do
                table.insert(
                    tools,
                    vim.tbl_extend("force", tool, {
                        server_name = server.name,
                    })
                )
            end
        end
    end
    return tools
end

function MCPHub:get_active_servers_prompt()
    if not self:ensure_ready() then
        return ""
    end
    return prompt_utils.get_active_servers_prompt(self:get_servers())
end

function MCPHub:get_use_mcp_tool_prompt(opts)
    if not self:ensure_ready() then
        return ""
    end
    return prompt_utils.get_use_mcp_tool_prompt(opts)
end

function MCPHub:get_access_mcp_resource_prompt(opts)
    if not self:ensure_ready() then
        return ""
    end
    return prompt_utils.get_access_mcp_resource_prompt(opts)
end

function MCPHub:get_state()
    return State
end

--- Get all MCP system prompts
---@param opts? {use_mcp_tool_example?: string, access_mcp_resource_example?: string}
---@return {active_servers: string|nil, use_mcp_tool: string|nil, access_mcp_resource: string|nil}
function MCPHub:get_prompts(opts)
    if not self:ensure_ready() then
        return {}
    end
    opts = opts or {}
    return {
        active_servers = self:get_active_servers_prompt(),
        use_mcp_tool = prompt_utils.get_use_mcp_tool_prompt(opts.use_mcp_tool_example),
        access_mcp_resource = prompt_utils.get_access_mcp_resource_prompt(opts.access_mcp_resource_example),
    }
end

--- Get marketplace catalog with filters
--- @param opts? { search?: string, category?: string, sort?: string, callback?: function, timeout?: number }
--- @return table|nil, string|nil If no callback is provided, returns response and error
function MCPHub:get_marketplace_catalog(opts)
    opts = opts or {}
    local query = {}

    -- Add filters to query if provided
    if opts.search then
        query.search = opts.search
    end
    if opts.category then
        query.category = opts.category
    end
    if opts.sort then
        query.sort = opts.sort
    end

    State:update({
        marketplace_state = {
            status = "loading",
        },
    }, "marketplace")
    -- Make request with market-specific error handling
    return self:api_request("GET", "marketplace", {
        timeout = opts.timeout or TOOL_TIMEOUT,
        query = query,
        callback = function(response, err)
            if err then
                local market_err = Error(
                    "MARKETPLACE",
                    Error.Types.MARKETPLACE.FETCH_ERROR,
                    "Failed to fetch marketplace catalog",
                    { error = err }
                )
                State:update({
                    marketplace_state = {
                        status = "error",
                    },
                }, "marketplace")
                return
            end

            -- Update marketplace state
            State:update({
                marketplace_state = {
                    status = "idle",
                    catalog = {
                        items = response.items or {},
                        last_updated = response.timestamp,
                    },
                },
            }, "marketplace")
        end,
    })
end

--- Get detailed information about a marketplace server
--- @param mcpId string The server's unique identifier
--- @param opts? { callback?: function, timeout?: number }
--- @return table|nil, string|nil If no callback is provided, returns response and error
function MCPHub:get_marketplace_server_details(mcpId, opts)
    opts = opts or {}

    -- Check if we have cached details that are still valid
    local cached = State.marketplace_state.server_details[mcpId]
    if cached then
        return cached
    end
    -- Fetch fresh details
    return self:api_request("POST", "marketplace/details", {
        timeout = opts.timeout or TOOL_TIMEOUT,
        body = { mcpId = mcpId },
        callback = function(response, err)
            if err then
                local market_err = Error(
                    "MARKETPLACE",
                    Error.Types.MARKETPLACE.FETCH_ERROR,
                    "Failed to fetch server details",
                    { mcpId = mcpId, error = err }
                )
                State:add_error(market_err)
                -- Keep server details as nil to indicate error state
            else
                -- Update state with new details
                State:update({
                    marketplace_state = {
                        server_details = {
                            [mcpId] = {
                                data = response.server,
                                timestamp = vim.loop.now(),
                            },
                        },
                    },
                }, "marketplace")
            end
        end,
    })
end

return MCPHub
