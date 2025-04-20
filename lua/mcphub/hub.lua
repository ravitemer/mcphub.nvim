local Error = require("mcphub.utils.errors")
local Job = require("plenary.job")
local State = require("mcphub.state")
local constants = require("mcphub.utils.constants")
local curl = require("plenary.curl")

local handlers = require("mcphub.utils.handlers")
local log = require("mcphub.utils.log")
local native = require("mcphub.native")
local prompt_utils = require("mcphub.utils.prompt")
local utils = require("mcphub.utils")
local validation = require("mcphub.utils.validation")

-- Default timeouts
local QUICK_TIMEOUT = 1000 -- 1s for quick operations like health checks
local TOOL_TIMEOUT = 30000 -- 30s for tool calls
local RESOURCE_TIMEOUT = 30000 -- 30s for resource access

--- @class MCPHub
--- @field port number The port number for the MCP Hub server
--- @field server_url string In case of hosting mcp-hub somewhere, the url with `https://mydomain.com:5858`
--- @field config string Path to the MCP servers configuration file
--- @field auto_toggle_mcp_servers boolean whether to enable LLM to start and stop MCP Servers
--- @field shutdown_delay number Delay in seconds before shutting down the server
--- @field cmd string The cmd to invoke the MCP Hub server
--- @field cmdArgs table The args to pass to the cmd to spawn the server
--- @field ready boolean Whether the connection to server is ready
--- @field server_job Job|nil The server process job if we started it
--- @field is_owner boolean Whether this instance started the server
--- @field is_shutting_down boolean Whether we're in the process of shutting down
--- @field on_ready fun(hub)
--- @field on_error fun(error:string)
local MCPHub = {}
MCPHub.__index = MCPHub

--- Create a new MCPHub instance
--- @param opts table Configuration options
--- @return MCPHub Instance of MCPHub
function MCPHub:new(opts)
    local self = setmetatable({}, MCPHub)

    -- Set up instance fields
    self.port = opts.port
    self.server_url = opts.server_url
    self.config = opts.config
    self.shutdown_delay = opts.shutdown_delay
    self.cmd = opts.cmd
    self.cmdArgs = opts.cmdArgs
    self.auto_toggle_mcp_servers = opts.auto_toggle_mcp_servers
    self.ready = false
    self.server_job = nil
    self.is_owner = false -- Whether we started the server
    self.is_shutting_down = false
    self.on_ready = opts.on_ready or function() end
    self.on_error = opts.on_error or function() end

    return self
end

--- Start the MCP Hub server
--- @param opts? { on_ready: function, on_error: function }
function MCPHub:start(opts, restart_callback)
    opts = opts or State.config

    -- Update state
    State:update_hub_state(constants.HubState.STARTING)

    -- Check if server is already running
    self:check_server(function(is_running, is_our_server)
        if is_running then
            if not is_our_server then
                self:handle_hub_error("Port in use by non-MCP Hub server")
                return
            end
            log.debug("MCP Hub already running")
            self:connect_sse()
            return
        end

        -- Try to start new server
        self.is_owner = true
        self.server_job = Job:new({
            command = self.cmd,
            args = utils.clean_args({
                self.cmdArgs,
                "--port",
                tostring(self.port),
                "--config",
                self.config,
                "--auto-shutdown",
                "--shutdown-delay",
                self.shutdown_delay or 0,
                "--watch",
            }),
            hide = true,
            on_stderr = vim.schedule_wrap(function(_, data)
                if data then
                    log.debug("Server stderr:" .. data)
                end
            end),
            on_start = vim.schedule_wrap(function()
                self:connect_sse()
            end),
            on_stdout = vim.schedule_wrap(function(_, data)
                -- if data then
                --     log.debug("Server stdout:" .. data)
                -- end
            end),
            on_exit = vim.schedule_wrap(function(j, code)
                if code ~= 0 and not self.is_shutting_down then
                    local stderr = table.concat(j:stderr_result() or {}, "\n")
                    if stderr:match("EADDRINUSE") then
                        -- Port was just taken, try connecting
                        log.debug("Port taken, trying to connect...")
                    else
                        local err_msg = "Server process exited with code " .. code
                        self:handle_hub_error(err_msg .. "\n" .. stderr, opts)
                    end
                end
            end),
        })

        self.server_job:start()
    end)
end

function MCPHub:handle_hub_ready()
    self.ready = true
    self.on_ready(self)
    self:update_servers()
    if State.marketplace_state.status == "empty" then
        self:get_marketplace_catalog()
    end
end

function MCPHub:_clean_up()
    if self.server_job then
        self.server_job = nil
    end
    self.is_owner = false
    self.ready = false
    State:update_hub_state(constants.HubState.STOPPED)
    self:fire_hub_update()
end
function MCPHub:handle_hub_error(msg)
    if self.is_shutting_down then
        return -- Skip error handling during shutdown
    end
    -- Create error object
    local err = Error("SERVER", Error.Types.SERVER.SERVER_START, msg)
    State:add_error(err)
    State:update_hub_state(constants.HubState.STOPPED)
    self.on_error(tostring(err))
    self:_clean_up()
end

--- Check if server is running and handle connection
--- @param callback? function Optional callback(is_running: boolean, is_our_server: boolean)
--- @return boolean If no callback is provided, returns is_running
function MCPHub:check_server(callback)
    log.debug("Checking Server")
    if self:is_ready() then
        callback(true, true)
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
            callback(false, false)
        else
            local is_hub_server = response and response.server_id == "mcp-hub" and response.status == "ok"
            log.debug("Got health response in check_server, is_hub_server? " .. tostring(is_hub_server))
            callback(true, is_hub_server) -- Running but may not be our server
        end
    end

    self:get_health(opts)
end

--- Get server status information
--- @param opts? { callback?: function } Optional callback(response: table|nil, error?: string)
--- @return table|nil, string|nil If no callback is provided, returns response and error
function MCPHub:get_health(opts)
    return self:api_request("GET", "health", opts)
end

--- Start a disabled/disconnected MCP server
---@param name string Server name to start
---@param opts? { via_curl_request?:boolean,callback?: function } Optional callback(response: table|nil, error?: string)
---@return table|nil, string|nil If no callback is provided, returns response and error
function MCPHub:start_mcp_server(name, opts)
    opts = opts or {}
    if not self:update_server_config(name, {
        disabled = false,
    }) then
        return
    end
    local is_native = native.is_native_server(name)
    if is_native then
        local server = is_native
        server:start()
        State:emit("servers_updated", {
            hub = self,
        })
    else
        for i, server in ipairs(State.server_state.servers) do
            if server.name == name then
                State.server_state.servers[i].status = "connecting"
                break
            end
        end

        --only if we want to send a curl request (otherwise file watch and sse events autoupdates)
        --This is needed in cases where users need to start the server and need to be sure if it is started or not rather than depending on just file watching
        --Note: this will update the config in the state in the backend which will not trigger file change event as this is sometimes updated before the file change event is triggered so the backend explicitly sends SubscriptionEvent with type servers_updated. which leads to "no signigicant changes" notification as well as "servers updated" notification as we send this explicitly.
        if opts.via_curl_request then
            -- Call start endpoint
            self:api_request("POST", "servers/start", {
                body = {
                    server_name = name,
                },
                callback = function(response, err)
                    self:refresh()
                    if opts.callback then
                        opts.callback(response, err)
                    end
                end,
            })
        end
    end
    State:notify_subscribers({
        server_state = true,
    }, "server")
end

--- Stop an MCP server
---@param name string Server name to stop
---@param disable boolean Whether to disable the server
---@param opts? { via_curl_request?: boolean, callback?: function } Optional callback(response: table|nil, error?: string)
---@return table|nil, string|nil If no callback is provided, returns response and error
function MCPHub:stop_mcp_server(name, disable, opts)
    opts = opts or {}

    if not self:update_server_config(name, {
        disabled = disable or false,
    }) then
        return
    end
    local is_native = native.is_native_server(name)
    if is_native then
        local server = is_native
        server:stop()
        State:emit("servers_updated", {
            hub = self,
        })
    else
        for i, server in ipairs(State.server_state.servers) do
            if server.name == name then
                State.server_state.servers[i].status = "disconnecting"
                break
            end
        end

        --only if we want to send a curl request (otherwise file watch and sse events autoupdates)
        if opts.via_curl_request then
            -- Call stop endpoint
            self:api_request("POST", "servers/stop", {
                query = disable and {
                    disable = "true",
                } or nil,
                body = {
                    server_name = name,
                },
                callback = function(response, err)
                    self:refresh()
                    if opts.callback then
                        opts.callback(response, err)
                    end
                end,
            })
        end
    end
    State:notify_subscribers({
        server_state = true,
    }, "server")
end

function MCPHub:fire_hub_update(data)
    -- Fire state change event with updated stats
    utils.fire("MCPHubStateChange", data or {
        state = State.server_state.state,
        active_servers = #self:get_servers(),
    })
end

--- Get a prompt from the server
--- @param server_name string
--- @param prompt_name string
--- @param args table
--- @param opts? { callback?: function, timeout?: number } Optional callback(response: table|nil, error?: string) and timeout in ms (default 30s)
--- @return table|nil, string|nil If no callback is provided, returns response and error
function MCPHub:get_prompt(server_name, prompt_name, args, opts)
    opts = opts or {}
    if opts.callback then
        local original_callback = opts.callback
        opts.callback = function(response, err)
            -- Signal prompt completion
            utils.fire("MCPHubPromptEnd", {
                server = server_name,
                prompt = prompt_name,
                success = err == nil,
            })
            if opts.parse_response == true then
                response = prompt_utils.parse_prompt_response(response)
            end
            original_callback(response, err)
        end
    end

    -- Signal prompt start
    utils.fire("MCPHubPromptStart", {
        server = server_name,
        prompt = prompt_name,
    })
    local arguments = args or vim.empty_dict()
    if vim.islist(arguments) or vim.isarray(arguments) then
        if #arguments == 0 then
            arguments = vim.empty_dict()
        else
            log.error("Arguments should be a dictionary, but got a list.")
            return
        end
    end
    --make sure we have an object
    -- Check native servers first
    local is_native = native.is_native_server(server_name)
    if is_native then
        local server = is_native
        local result, err = server:get_prompt(prompt_name, args, opts)
        if opts.callback == nil then
            utils.fire("MCPHubPromptEnd", {
                server = server_name,
                prompt = prompt_name,
                success = err == nil,
            })
            return (opts.parse_response == true and prompt_utils.parse_prompt_response(result) or result), err
        end
        return
    end

    local response, err = self:api_request(
        "POST",
        "servers/prompts",
        vim.tbl_extend("force", {
            timeout = opts.timeout or TOOL_TIMEOUT,
            body = {
                server_name = server_name,
                prompt = prompt_name,
                arguments = arguments,
            },
        }, opts)
    )

    -- handle sync calls
    if opts.callback == nil then
        utils.fire("MCPHubPromptEnd", {
            server = server_name,
            prompt = prompt_name,
            success = err == nil,
        })
        return (opts.parse_response == true and prompt_utils.parse_prompt_response(response) or response), err
    end
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
            -- Signal tool completion
            utils.fire("MCPHubToolEnd", {
                server = server_name,
                tool = tool_name,
                success = err == nil,
            })
            if opts.parse_response == true then
                response = prompt_utils.parse_tool_response(response)
            end
            original_callback(response, err)
        end
    end

    -- Signal tool start
    utils.fire("MCPHubToolStart", {
        server = server_name,
        tool = tool_name,
    })
    local arguments = args or vim.empty_dict()
    if vim.islist(arguments) or vim.isarray(arguments) then
        if #arguments == 0 then
            arguments = vim.empty_dict()
        else
            log.error("Arguments should be a dictionary, but got a list.")
            return
        end
    end
    -- Check native servers first
    local is_native = native.is_native_server(server_name)
    if is_native then
        local server = is_native
        local result, err = server:call_tool(tool_name, args, opts)
        if opts.callback == nil then
            utils.fire("MCPHubToolEnd", {
                server = server_name,
                tool = tool_name,
                success = err == nil,
            })
            return (opts.parse_response == true and prompt_utils.parse_tool_response(result) or result), err
        end
        return
    end

    local response, err = self:api_request(
        "POST",
        "servers/tools",
        vim.tbl_extend("force", {
            timeout = opts.timeout or TOOL_TIMEOUT,
            body = {
                server_name = server_name,
                tool = tool_name,
                arguments = arguments,
            },
        }, opts)
    )

    -- handle sync calls
    if opts.callback == nil then
        utils.fire("MCPHubToolEnd", {
            server = server_name,
            tool = tool_name,
            success = err == nil,
        })
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
            -- Signal resource completion
            utils.fire("MCPHubResourceEnd", {
                server = server_name,
                uri = uri,
                success = err == nil,
            })
            if opts.parse_response == true then
                response = prompt_utils.parse_resource_response(response)
            end
            original_callback(response, err)
        end
    end

    -- Signal resource start
    utils.fire("MCPHubResourceStart", {
        server = server_name,
        uri = uri,
    })

    -- Check native servers first
    local is_native = native.is_native_server(server_name)
    if is_native then
        local server = is_native
        local result, err = server:access_resource(uri, opts)
        if opts.callback == nil then
            utils.fire("MCPHubResourceEnd", {
                server = server_name,
                uri = uri,
                success = err == nil,
            })
            return (opts.parse_response == true and prompt_utils.parse_resource_response(result) or result), err
        end
        return
    end

    -- Otherwise proxy to MCP server
    local response, err = self:api_request(
        "POST",
        "servers/resources",
        vim.tbl_extend("force", {
            timeout = opts.timeout or RESOURCE_TIMEOUT,
            body = {
                server_name = server_name,
                uri = uri,
            },
        }, opts)
    )
    -- handle sync calls
    if opts.callback == nil then
        utils.fire("MCPHubResourceEnd", {
            server = server_name,
            uri = uri,
            success = err == nil,
        })
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
    -- the url of the mcp-hub server if it is hosted somewhere (e.g. https://mydomain.com)
    local base_url = self.server_url or string.format("http://localhost:%d", self.port)
    --remove any trailing slashes
    base_url = base_url:gsub("/+$", "")

    -- Build URL with query parameters if any
    local url = string.format("%s/api/%s", base_url, path)
    if opts.query then
        local params = {}
        for k, v in pairs(opts.query) do
            table.insert(params, k .. "=" .. v)
        end
        url = url .. "?" .. table.concat(params, "&")
    end

    local raw = {}
    if opts.timeout then
        vim.list_extend(raw, { "--connect-timeout", tostring(opts.timeout / 1000) })
    end

    -- Prepare request options
    local request_opts = {
        url = url,
        method = method,
        --INFO: generating custom headers file path to avoid getting .header file not found when simulataneous requests are sent
        dump = utils.gen_dump_path(),
        headers = {
            ["Content-Type"] = "application/json",
            ["Accept"] = "application/json",
        },
        raw = raw,
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
        --
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

function MCPHub:load_config()
    local result = validation.validate_config_file(self.config)
    if not result.ok then
        if result.error then
            State:add_error(result.error)
        end
        return nil, result.error.message
    end

    local config = result.json
    -- Ensure mcpServers exists
    config.mcpServers = config.mcpServers or {}
    config.nativeMCPServers = config.nativeMCPServers or {}
    return config
end

function MCPHub:refresh_config()
    self:refresh_native_servers()
    self:fire_hub_update()
end

-- make sure we update the native servers disabled status when the servers are updated through a sse event
-- TODO: think of a better approach
function MCPHub:refresh_native_servers()
    local config = self:load_config()
    if not config then
        return
    end
    for _, server in ipairs(State.server_state.native_servers) do
        local server_config = config.nativeMCPServers[server.name] or {}
        local is_enabled = server_config.disabled ~= true
        if not is_enabled then
            server:stop()
        else
            server:start()
        end
    end
    -- Update State
    State:update({
        servers_config = config.mcpServers,
        native_servers_config = config.nativeMCPServers,
    }, "setup")
end

function MCPHub:update_servers(servers, callback)
    callback = callback or function() end
    local function update_state(_servers)
        State:update({
            server_state = {
                servers = _servers or {},
            },
        }, "server")
        -- Fire state change event with updated stats
        self:fire_hub_update()
        -- Emit server update event with prompt
        State:emit("servers_updated", {
            hub = self,
        })
    end
    --even we change native server status we need to emit so that ui updates, so update_servers takes care of that
    self:refresh_native_servers()
    if servers then
        update_state(servers)
    else
        self:get_health({
            callback = function(response, err)
                if err then
                    local health_err = Error("SERVER", Error.Types.SERVER.HEALTH_CHECK, "Health check failed", {
                        error = err,
                    })
                    State:add_error(health_err)
                    callback(false)
                else
                    update_state(response.servers or {})
                    callback(true)
                end
            end,
        })
    end
end

function MCPHub:handle_capability_updates(data)
    local type = data.type
    local server = data.server
    local map = {
        [constants.SubscriptionTypes.TOOL_LIST_CHANGED] = { "tools" },
        [constants.SubscriptionTypes.RESOURCE_LIST_CHANGED] = { "resources", "resourceTemplates" },
        [constants.SubscriptionTypes.PROMPT_LIST_CHANGED] = { "prompts" },
    }
    local fields_to_update = map[type]
    if not fields_to_update then
        log.warn("Unknown capability update type: " .. type)
        return
    end
    if not server then
        return
    end
    for _, s in ipairs(State.server_state.servers) do
        if s.name == server then
            local emit_data = {
                server = server,
                hub = self,
            }
            for _, field in ipairs(fields_to_update) do
                s.capabilities[field] = data[field] or {}
                emit_data[field] = s.capabilities[field]
            end
            State.emit(type, emit_data)
            break
        end
    end
    -- Notify subscribers of state change
    State:notify_subscribers({
        server_state = true,
    }, "server")
end

--- Update server configuration in the MCP config file
---@param server_name string Name of the server to update
---@param updates table|nil Key-value pairs to update in the server config or nil to remove
---@param opts? { callback?: function } Optional callback(success: boolean)
function MCPHub:update_server_config(server_name, updates, opts)
    opts = opts or {}
    -- Load and validate current config
    local config = self:load_config()
    if not config then
        return
    end
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
    -- Stop SSE connection
    self:stop_sse()
    self:_clean_up()
    self.is_shutting_down = false
end

function MCPHub:is_ready()
    return self.ready
end

--- Connect to SSE events endpoint
function MCPHub:connect_sse()
    if self.sse_job then
        return
    end
    local buffer = ""
    local base_url = self.server_url or string.format("http://localhost:%d", self.port)
    base_url = base_url:gsub("/+$", "")

    -- Create SSE connection
    local sse_job = Job:new({
        command = "curl",
        args = {
            "--no-buffer",
            "--tcp-nodelay",
            "--retry",
            "5",
            "--retry-delay",
            "1",
            "--retry-connrefused",
            "--keepalive-time",
            "60",
            base_url .. "/api/events",
        },
        on_stdout = vim.schedule_wrap(function(_, data)
            if data ~= nil then
                buffer = buffer .. data .. "\n"

                while true do
                    local event_end = buffer:find("\n\n")
                    if not event_end then
                        break
                    end

                    local event_str = buffer:sub(1, event_end - 1)
                    buffer = buffer:sub(event_end + 2)

                    local event = event_str:match("^event: (.-)\n")
                    local data_line = event_str:match("\ndata: ([^\r\n]+)")

                    if event and data_line then
                        local success, decoded = pcall(vim.fn.json_decode, data_line)
                        if success then
                            log.trace(string.format("SSE event: %s", event))
                            handlers.SSEHandlers.handle_sse_event(event, decoded, self, opts)
                        else
                            log.warn(string.format("Failed to decode SSE data: %s", data_line))
                        end
                    else
                        log.warn(string.format("Malformed SSE event: %s", event_str))
                    end
                end
            end
        end),
        on_stderr = vim.schedule_wrap(function(j, data)
            log.debug("SSE STDERR: " .. tostring(data))
        end),
        on_exit = vim.schedule_wrap(function(j, code)
            log.debug("SSE JOB exited with " .. tostring(code))
            -- if code ~= 0 and not self.is_shutting_down then
            if not self.is_shutting_down then
                self:handle_hub_error("SSE connection failed with code " .. tostring(code))
            end
            self.sse_job = nil
        end),
    })

    -- Store SSE job for cleanup
    self.sse_job = sse_job
    sse_job:start()
end

--- Stop SSE connection
function MCPHub:stop_sse()
    if self.sse_job then
        self.sse_job:shutdown(0)
        self.sse_job = nil
    end
end

function MCPHub:refresh(callback)
    callback = callback or function() end
    self:update_servers(nil, callback)
end

function MCPHub:hard_refresh(callback)
    callback = callback or function() end
    if not self:ensure_ready() then
        return
    end
    self:api_request("GET", "refresh", {
        callback = function(response, err)
            if err then
                local health_err = Error("SERVER", Error.Types.SERVER.HEALTH_CHECK, "Hard Refresh failed : " .. err, {
                    error = err,
                })
                State:add_error(health_err)
                callback(false)
            else
                self:update_servers(response.servers or {})
                callback(true)
            end
        end,
    })
end

function MCPHub:handle_hub_restarting()
    State:update({
        errors = {
            items = {},
        },
        server_output = {
            entries = {},
        },
    }, "server")
    self:fire_hub_update()
end

function MCPHub:restart(callback)
    if not self:ensure_ready() then
        return
    end
    self:api_request("POST", "restart", {
        callback = function(response, err)
            if err then
                local restart_err = Error("SERVER", Error.Types.SERVER.RESTART, "Restart failed", {
                    error = err,
                })
                State:add_error(restart_err)
                self:refresh() --get latest status
                if callback then
                    callback(false)
                end
                return
            end
            if callback then
                callback(true)
            end
        end,
    })
end

function MCPHub:ensure_ready()
    if not self:is_ready() then
        log.warn("Hub is not ready.")
        return false
    end
    return true
end

--- Get servers with their tools filtered based on server config
---@return table[] Array of connected servers with disabled tools filtered out
-- Helper to filter server capabilities based on config
local function filter_server_capabilities(server, config)
    local filtered_server = vim.deepcopy(server)

    if filtered_server.capabilities then
        -- Common function to filter capabilities
        local function filter_capabilities(capabilities, disabled_list, id_field)
            return vim.tbl_filter(function(item)
                return not vim.tbl_contains(disabled_list, item[id_field])
            end, capabilities)
        end

        -- Filter all capability types with their respective config fields
        local capability_filters = {
            tools = { list = "disabled_tools", id = "name" },
            resources = { list = "disabled_resources", id = "uri" },
            resourceTemplates = { list = "disabled_resourceTemplates", id = "uriTemplate" },
            prompts = { list = "disabled_prompts", id = "name" },
        }

        for cap_type, filter in pairs(capability_filters) do
            if filtered_server.capabilities[cap_type] then
                filtered_server.capabilities[cap_type] =
                    filter_capabilities(filtered_server.capabilities[cap_type], config[filter.list] or {}, filter.id)
            end
        end
    end
    return filtered_server
end

---resolve any functions in the native servers
---@param native_server NativeServer
---@return table
local function resolve_native_server(native_server)
    local server = vim.deepcopy(native_server)
    local possible_func_fields = {
        tools = { "description", "inputSchema" },
        resources = { "description" },
        resourceTemplates = { "description" },
        prompts = { "description" },
    }
    --first resolve the server desc itself
    server.description = prompt_utils.get_description(server)

    for cap_type, fields in pairs(possible_func_fields) do
        for _, capability in ipairs(server.capabilities[cap_type] or {}) do
            --remove handler as it is not in std protocol
            capability.handler = nil
            for _, field in ipairs(fields) do
                if capability[field] then
                    if field == "description" then --resolves to string
                        capability[field] = prompt_utils.get_description(capability)
                    elseif field == "inputSchema" then --resolves to inputSchema table
                        capability[field] = prompt_utils.get_inputSchema(capability)
                    end
                end
            end
        end
    end
    return server
end

function MCPHub:get_servers(include_disabled)
    include_disabled = include_disabled == true
    if not self:is_ready() then
        return {}
    end
    local filtered_servers = {}

    -- Add regular MCP servers
    for _, server in ipairs(State.server_state.servers or {}) do
        if server.status == "connected" or include_disabled then
            local server_config = State.servers_config[server.name] or {}
            local filtered_server = filter_server_capabilities(server, server_config)
            table.insert(filtered_servers, filtered_server)
        end
    end

    -- Add native servers
    for _, server in ipairs(State.server_state.native_servers or {}) do
        if server.status == "connected" or include_disabled then
            local server_config = State.native_servers_config[server.name] or {}
            local filtered_server = filter_server_capabilities(server, server_config)
            --INFO: this is for cases where chat plugins expect std MCP definations to remove mcphub specific enhancements
            local resolved_server = resolve_native_server(filtered_server)
            table.insert(filtered_servers, resolved_server)
        end
    end

    return filtered_servers
end

function MCPHub:get_prompts()
    local active_servers = self:get_servers()
    local prompts = {}
    for _, server in ipairs(active_servers) do
        if server.capabilities and server.capabilities.prompts then
            for _, prompt in ipairs(server.capabilities.prompts) do
                table.insert(
                    prompts,
                    vim.tbl_extend("force", prompt, {
                        server_name = server.name,
                    })
                )
            end
        end
    end
    return prompts
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

function MCPHub:get_resource_templates()
    local active_servers = self:get_servers()
    local resource_templates = {}
    for _, server in ipairs(active_servers) do
        if server.capabilities and server.capabilities.resourceTemplates then
            for _, resource_template in ipairs(server.capabilities.resourceTemplates) do
                table.insert(
                    resource_templates,
                    vim.tbl_extend("force", resource_template, {
                        server_name = server.name,
                    })
                )
            end
        end
    end
    return resource_templates
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

function MCPHub:convert_server_to_text(server)
    local is_native = native.is_native_server(server.name)
    local server_config = is_native and State.native_servers_config[server.name] or State.servers_config[server.name]
    local filtered_server = filter_server_capabilities(server, server_config)
    return prompt_utils.server_to_text(filtered_server)
end

function MCPHub:get_active_servers_prompt(add_example, include_disabled)
    include_disabled = include_disabled ~= nil and include_disabled or self.auto_toggle_mcp_servers
    add_example = add_example ~= false
    if not self:is_ready() then
        return ""
    end
    return prompt_utils.get_active_servers_prompt(self:get_servers(include_disabled), add_example, include_disabled)
end

--- Get all MCP system prompts
---@param opts? {use_mcp_tool_example?: string, add_example?: boolean, include_disabled?: boolean, access_mcp_resource_example?: string}
---@return {active_servers: string|nil, use_mcp_tool: string|nil, access_mcp_resource: string|nil}
function MCPHub:generate_prompts(opts)
    if not self:ensure_ready() then
        return {}
    end
    opts = opts or {}
    return {
        active_servers = self:get_active_servers_prompt(opts.add_example, opts.include_disabled),
        use_mcp_tool = prompt_utils.get_use_mcp_tool_prompt(opts.use_mcp_tool_example),
        access_mcp_resource = prompt_utils.get_access_mcp_resource_prompt(opts.access_mcp_resource_example),
    }
end

--- Get marketplace catalog with filters
--- @param opts? { search?: string, category?: string, sort?: string, callback?: function, timeout?: number }
--- @return table|nil, string|nil If no callback is provided, returns response and error
function MCPHub:get_marketplace_catalog(opts)
    if State.marketplace_state.status == "loading" then
        return
    end
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
                State:add_error(market_err)
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
                    status = "loaded",
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
