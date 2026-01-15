local M = {}

--- Get proxy command and args for external MCP clients
---@return { command: string, args: string[] }
function M.get()
    local State = require("mcphub.state")
    local config = require("mcphub.config")

    local plugin_root = vim.fn.fnamemodify(debug.getinfo(1).source:sub(2), ":h:h:h:h:h")
    local scripts_dir = plugin_root .. "/scripts"
    local script_path = scripts_dir .. "/proxy.js"

    local command = "node"
    local args = {
        script_path,
        "--socket",
        vim.v.servername,
    }

    if State.config.mcp_request_timeout then
        vim.list_extend(args, { "--rpc-call-timeout", tostring(State.config.mcp_request_timeout) })
    end

    vim.list_extend(args, { "--log-level", tostring(config.log.level) })

    if config.log.to_file and config.log.file_path then
        vim.list_extend(args, { "--log-file", config.log.file_path })
    end

    return {
        command = command,
        args = args,
    }
end

--- Get all servers available.
---@return table[]
function M.get_all_servers()
    local mcphub = require("mcphub")
    local hub = mcphub.get_hub_instance()

    if not hub or not hub:is_ready() then
        return {}
    end

    local servers = hub:get_servers()

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

--- Call a tool via instance.
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
    local caller = params.caller or { type = "external" }

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

--- Access a resource via instance.
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

    local caller = params.caller or { type = "external" }

    local result, err = hub:access_resource(server_name, uri, {
        parse_response = false,
        caller = caller,
    })

    if err then
        return { error = err }
    end

    if result and result.result then
        return result.result
    end

    return result
end

--- Get a prompt via instance.
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
    local caller = params.caller or { type = "external" }

    local result, err = hub:get_prompt(server_name, prompt_name, arguments, {
        parse_response = false,
        caller = caller,
    })

    if err then
        return { error = err }
    end

    if result and result.result then
        return result.result
    end

    return result
end

return M
