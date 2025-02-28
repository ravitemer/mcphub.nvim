local curl = require("plenary.curl")
local Job = require("plenary.job")
local log = require("mcphub.utils.log")
local prompt_utils = require("mcphub.utils.prompt")
local handlers = require("mcphub.utils.handlers")
local State = require("mcphub.state")
local Error = require("mcphub.errors")

-- Default timeouts
local QUICK_TIMEOUT = 1000 -- 1s for quick operations like health checks
local TOOL_TIMEOUT = 30000 -- 30s for tool calls
local RESOURCE_TIMEOUT = 30000 -- 30s for resource access

--- @class MCPHub
--- @field port number The port number for the MCP Hub server
--- @field config string Path to the MCP servers configuration file
--- @field ready boolean Whether the connection to server is ready
--- @field server_job Job|nil The server process job if we started it
--- @field client_id string Unique identifier for this client
--- @field is_owner boolean Whether this instance started the server
--- @field is_shutting_down boolean Whether we're in the process of shutting down
local MCPHub = {}
MCPHub.__index = MCPHub

--- Create a new MCPHub instance
--- @param opts table Configuration options
--- @return MCPHub Instance of MCPHub
function MCPHub:new(opts)
    local self = setmetatable({}, MCPHub)

    -- Set up instance fields
    self.port = opts.port
    self.config = opts.config
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
            pid = nil
        }
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
            status = "connecting"
        }
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

        self.server_job = Job:new({
            command = "mcp-hub",
            args = {"--port", tostring(self.port), "--config", self.config},
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
                        pid = nil
                    }
                }, "server")

                self.ready = false
                self.server_job = nil
            end)
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
            pid = self.server_job and self.server_job.pid
        }
    }, "server")

    -- update the state
    self:get_health({
        callback = function(response, err)
            if err then
                if self:is_ready() then
                    local health_err = Error("SERVER", Error.Types.SERVER.HEALTH_CHECK, "Health check failed", {
                        error = err
                    })
                    State:add_error(health_err)
                end
            else
                State:update({
                    server_state = vim.tbl_extend("force", State.server_state, {
                        servers = response.servers or {}
                    })
                }, "server")

                -- Register client
                self:register_client({
                    callback = function(response, reg_err)
                        if reg_err then
                            local err = Error("SERVER", Error.Types.SERVER.CONNECTION, "Client registration failed", {
                                error = reg_err
                            })
                            State:add_error(err)
                            if opts.on_error then
                                opts.on_error(tostring(err))
                            end
                            return
                        end
                        if opts.on_ready then
                            opts.on_ready(self)
                        end
                    end
                })
            end
        end
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
        log.debug("hub is ready, no need to checkserver")
        callback(true)
        return
    end

    -- Quick health check
    local opts = {
        timeout = QUICK_TIMEOUT,
        skip_ready_check = true
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
    return self:api_request("POST", "client/register", vim.tbl_extend("force", {
        body = {
            clientId = self.client_id
        }
    }, opts or {}))
end

--- Get server status information
--- @param opts? { callback?: function } Optional callback(response: table|nil, error?: string)
--- @return table|nil, string|nil If no callback is provided, returns response and error
function MCPHub:get_health(opts)
    return self:api_request("GET", "health", opts)
end

--- Get available servers
--- @param opts? { callback?: function } Optional callback(response: table|nil, error?: string)
--- @return table|nil, string|nil If no callback is provided, returns response and error
function MCPHub:get_servers(opts)
    return self:api_request("GET", "servers", opts)
end

--- Get server information if available
--- @param name string Server name
--- @param opts? { callback?: function } Optional callback(response: table|nil, error?: string)
--- @return table|nil, string|nil If no callback is provided, returns response and error
function MCPHub:get_server_info(name, opts)
    return self:api_request("GET", string.format("servers/%s/info", name), opts)
end

--- Call a tool on a server
--- @param server_name string
--- @param tool_name string
--- @param args table
--- @param opts? { callback?: function, timeout?: number } Optional callback(response: table|nil, error?: string) and timeout in ms (default 30s)
--- @return table|nil, string|nil If no callback is provided, returns response and error
function MCPHub:call_tool(server_name, tool_name, args, opts)
    opts = opts or {}
    if opts.return_text == true then
        if opts.callback then
            local original_callback = opts.callback
            opts.callback = function(response, err)
                local text = prompt_utils.parse_tool_response(response)
                original_callback(text, err)
            end
        end
    end
    -- ensure args is treated as an object in json
    local arguments = args or {}
    if vim.tbl_isempty(arguments) then
        -- add a property that will force encoding as an object
        arguments.__object = true
    end

    local response, err = self:api_request("POST", string.format("servers/%s/tools", server_name),
        vim.tbl_extend("force", {
            timeout = opts.timeout or TOOL_TIMEOUT,
            body = {
                tool = tool_name,
                arguments = arguments
            }
        }, opts))
    -- handle sync calls
    if opts.callback == nil then
        return (opts.return_text == true and prompt_utils.parse_tool_response(response) or response), err
    end
end

--- Access a server resource
--- @param server_name string
--- @param uri string
--- @param opts? { callback?: function, timeout?: number } Optional callback(response: table|nil, error?: string) and timeout in ms (default 30s)
--- @return table|nil, string|nil If no callback is provided, returns response and error
function MCPHub:access_resource(server_name, uri, opts)
    opts = opts or {}
    if opts.return_text == true then
        if opts.callback then
            local original_callback = opts.callback
            opts.callback = function(response, err)
                local text = prompt_utils.parse_resource_response(response)
                original_callback(text, err)
            end
        end
    end
    local response, err = self:api_request("POST", string.format("servers/%s/resources", server_name),
        vim.tbl_extend("force", {
            timeout = opts.timeout or RESOURCE_TIMEOUT,
            body = {
                uri = uri
            }
        }, opts))
    -- handle sync calls
    if opts.callback == nil then
        return (opts.return_text == true and prompt_utils.parse_resource_response(response) or response), err
    end
end

--- API request helper
--- @param method string HTTP method
--- @param path string API path
--- @param opts? { body?: table, timeout?: number, skip_ready_check?: boolean, callback?: function }
--- @return table|nil, string|nil If no callback is provided, returns response and error
function MCPHub:api_request(method, path, opts)
    opts = opts or {}
    local callback = opts.callback

    -- Prepare request options
    local request_opts = {
        url = string.format("http://localhost:%d/api/%s", self.port, path),
        method = method,
        timeout = opts.timeout or QUICK_TIMEOUT,
        headers = {
            ["Content-Type"] = "application/json",
            ["Accept"] = "application/json"
        },
        on_error = vim.schedule_wrap(function(err)
            log.debug(string.format("Error while making request to %s: %s", path, vim.inspect(err)))
            local error = handlers.ResponseHandlers.process_error(err, {
                code = "NETWORK_ERROR",
                request = request_opts
            })
            if not self:is_ready() and path == "health" then
                callback(nil, tostring(error))
            else
                State:add_error(error)
            end
        end)
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
            end)
        }))
    else
        -- Sync mode
        return process_response(curl.request(request_opts))
    end
end

--- Stop the MCP Hub server
--- Stops the server if we own it, otherwise just disconnects
function MCPHub:stop()
    self.is_shutting_down = true

    -- Unregister client
    self:api_request("POST", "client/unregister", {
        body = {
            clientId = self.client_id
        }
    })

    if self.is_owner then
        if self.server_job then
            self.server_job:shutdown()
        end
    end

    State:update({
        server_state = {
            status = "disconnected",
            pid = nil
        }
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
        if self:is_ready() then
            local health_err = Error("SERVER", Error.Types.SERVER.HEALTH_CHECK, "Health check failed", {
                error = err
            })
            State:add_error(health_err)
        end
        return false
    else
        State:update({
            server_state = vim.tbl_extend("force", State.server_state, {
                servers = response.servers or {}
            })
        }, "server")
        return true
    end
end

function MCPHub:restart(callback)
    if not self:ensure_ready() then
        return
    end
    self:stop()
    State:reset()
    local restart_callback = function(success)
        callback(success)
    end
    self:start(nil, restart_callback)
end

function MCPHub:ensure_ready()
    if not self:is_ready() then
        log.error("Server not ready. Make sure you call display after ensuring the mcphub is ready.")
        return false
    end
    return true
end

function MCPHub:get_active_servers_prompt()
    if not self:ensure_ready() then
        return ""
    end
    return prompt_utils.get_active_servers_prompt(State.server_state.servers or {})
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

--- Get all MCP system prompts
---@param opts? {use_mcp_tool_example?: string, access_mcp_resource_example?: string}
---@return {active_servers: string|nil, use_mcp_tool: string, access_mcp_resource: string}
function MCPHub:get_prompts(opts)
    if not self:ensure_ready() then
        return
    end
    opts = opts or {}
    return {
        active_servers = prompt_utils.get_active_servers_prompt(State.server_state.servers or {}),
        use_mcp_tool = prompt_utils.get_use_mcp_tool_prompt(opts.use_mcp_tool_example),
        access_mcp_resource = prompt_utils.get_access_mcp_resource_prompt(opts.access_mcp_resource_example)
    }
end

return MCPHub
