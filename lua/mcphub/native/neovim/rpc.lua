local M = {}

local log = require("mcphub.utils.log")

--- Start the proxy as a standalone process (not managed by mcp-hub)
---@param context table Hub context with port and workspace info
---@param rpc_timeout number RPC call timeout in milliseconds
---@return Job|nil, string|nil, string|nil job, proxy_socket, error
function M.start_proxy_server(context, rpc_timeout)
    local Job = require("plenary.job")

    local nvim_socket = vim.v.servername
    if not nvim_socket or nvim_socket == "" then
        nvim_socket = vim.fn.tempname()
        vim.fn.serverstart(nvim_socket)
        log.debug("Created Neovim RPC socket for proxy: " .. nvim_socket)
    end

    -- Create unique proxy socket path using temp file
    -- This ensures uniqueness and automatic cleanup on system restart
    local proxy_socket = vim.fn.tempname() .. ".sock"

    -- Get the path to the proxy script
    local plugin_root = vim.fn.fnamemodify(debug.getinfo(1).source:sub(2), ":h:h:h:h:h")
    local scripts_dir = plugin_root .. "/scripts"
    local script_path = scripts_dir .. "/proxy.js"

    -- Build args with optional timeout flag
    local args = { script_path, proxy_socket }
    if rpc_timeout then
        table.insert(args, "--rpc-call-timeout")
        table.insert(args, tostring(rpc_timeout))
    end

    -- Start proxy as standalone process
    local proxy_job = Job:new({
        command = "node",
        args = args,
        cwd = scripts_dir,
        env = {
            NVIM = nvim_socket,
        },
        on_exit = function(job, return_val)
            log.debug(string.format("Proxy process exited with code %d", return_val))
            -- Clean up socket file
            vim.fn.delete(proxy_socket)
        end,
        on_stderr = function(_, data)
            log.debug("Proxy: " .. data)
        end,
    })

    -- Start the job
    proxy_job:start()

    log.info(string.format("Started standalone RPC proxy process (PID: %d) on socket: %s", proxy_job.pid, proxy_socket))

    return proxy_job, proxy_socket, nil
end

--- RPC Bridge Functions for proxy.js to access the hub
--- These functions route requests through the hub, which handles both native and HTTP servers

--- Get all servers (native + HTTP) via hub
---@return table[] List of all servers with capabilities
function M.get_all_servers()
    local mcphub = require("mcphub")
    local hub = mcphub.get_hub_instance()

    if not hub or not hub:is_ready() then
        log.warn("Hub is not ready, returning empty server list")
        return {}
    end

    local servers = hub:get_servers()

    -- Format servers for RPC proxy
    local formatted_servers = {}
    for _, server in ipairs(servers) do
        table.insert(formatted_servers, {
            name = server.name,
            displayName = server.displayName,
            description = server.description,
            status = server.status,
            capabilities = {
                tools = vim.tbl_map(function(t)
                    return {
                        name = t.name,
                        description = t.description,
                        inputSchema = t.inputSchema,
                    }
                end, server.capabilities.tools or {}),
                resources = vim.tbl_map(function(r)
                    return {
                        uri = r.uri,
                        name = r.name,
                        description = r.description,
                        mimeType = r.mimeType,
                    }
                end, server.capabilities.resources or {}),
                prompts = vim.tbl_map(function(p)
                    return {
                        name = p.name,
                        description = p.description,
                        arguments = p.arguments,
                    }
                end, server.capabilities.prompts or {}),
            },
        })
    end

    return formatted_servers
end

--- Call a tool via hub (routes to native or HTTP server)
---@param server_name string Name of the server
---@param tool_name string Name of the tool
---@param params table Parameters including arguments and caller context
---@return table Result or error
function M.hub_call_tool(server_name, tool_name, params)
    local mcphub = require("mcphub")
    local hub = mcphub.get_hub_instance()

    if not hub or not hub:is_ready() then
        return { error = "Hub is not ready" }
    end

    local arguments = params.arguments or {}
    local caller = params.caller or { type = "external", source = "rpc-proxy" }

    -- Call via hub (synchronous)
    local result, err = hub:call_tool(server_name, tool_name, arguments, {
        parse_response = false,
        caller = caller,
    })

    if err then
        return { error = err }
    end

    -- Unwrap if needed (hub wraps responses in { result = ... })
    if result and result.result then
        return result.result
    end
    return result
end

--- Access a resource via hub (routes to native or HTTP server)
---@param server_name string Name of the server
---@param uri string Resource URI
---@param params? table Optional parameters including caller context
---@return table Result or error
function M.hub_access_resource(server_name, uri, params)
    params = params or {}
    local mcphub = require("mcphub")
    local hub = mcphub.get_hub_instance()

    if not hub or not hub:is_ready() then
        return { error = "Hub is not ready" }
    end

    local caller = params.caller or { type = "external", source = "rpc-proxy" }

    -- Call via hub (synchronous)
    local result, err = hub:access_resource(server_name, uri, {
        parse_response = false,
        caller = caller,
    })

    if err then
        return { error = err }
    end

    -- Unwrap if needed
    if result and result.result then
        return result.result
    end
    return result
end

--- Get a prompt via hub (routes to native or HTTP server)
---@param server_name string Name of the server
---@param prompt_name string Name of the prompt
---@param params table Parameters including arguments and caller context
---@return table Result or error
function M.hub_get_prompt(server_name, prompt_name, params)
    local mcphub = require("mcphub")
    local hub = mcphub.get_hub_instance()

    if not hub or not hub:is_ready() then
        return { error = "Hub is not ready" }
    end

    local arguments = params.arguments or {}
    local caller = params.caller or { type = "external", source = "rpc-proxy" }

    -- Call via hub (synchronous)
    local result, err = hub:get_prompt(server_name, prompt_name, arguments, {
        parse_response = false,
        caller = caller,
    })

    if err then
        return { error = err }
    end

    -- Unwrap if needed
    if result and result.result then
        return result.result
    end
    return result
end

return M
