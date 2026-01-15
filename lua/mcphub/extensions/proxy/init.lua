local M = {}

local shared = require("mcphub.extensions.shared")

--- Get proxy command and args for external MCP clients
---@return { command: string, args: string[] }
function M.get()
    local State = require("mcphub.state")

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

    vim.list_extend(args, { "--log-level", tostring(State.config.log.level) })

    if State.config.log.to_file and State.config.log.file_path then
        vim.list_extend(args, { "--log-file", State.config.log.file_path })
    end

    return {
        name = "mcphub",
        type = "stdio",
        command = command,
        args = args,
        url = "",
        headers = {},
        env = {},
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

--- Send result back to proxy.js via notification
---@param request_id string The request ID to respond to
---@param result table The result to send
local function send_result(request_id, result)
    vim.rpcnotify(0, "mcphub_proxy_result", request_id, result)
end

--- Async version of call_tool for proxy (uses nice UI)
---@param request_id string Request ID for async response
---@param server_name string Name of the server
---@param tool_name string Name of the tool
---@param params table Parameters including arguments and caller context
function M.call_tool(request_id, server_name, tool_name, params)
    local async = require("plenary.async")

    async.run(function()
        local mcphub = require("mcphub")
        local hub = mcphub.get_hub_instance()

        if not hub or not hub:is_ready() then
            send_result(request_id, { error = "Hub is not ready" })
            return
        end

        local arguments = params.arguments or {}
        local caller = params.caller or { type = "proxy" }

        -- Parse and validate params
        local parsed_params = shared.parse_params({
            server_name = server_name,
            tool_name = tool_name,
            tool_input = arguments,
        }, "use_mcp_tool")

        if #parsed_params.errors > 0 then
            send_result(request_id, { error = table.concat(parsed_params.errors, "\n") })
            return
        end

        -- Use the async approval with nice UI!
        local approval = shared.handle_auto_approval_decision(parsed_params)
        if approval.error then
            send_result(request_id, { error = approval.error })
            return
        end

        local result, err = hub:call_tool(server_name, tool_name, arguments, {
            parse_response = false,
            caller = vim.tbl_extend("force", caller, { auto_approve = approval.approve }),
        })

        if err then
            send_result(request_id, { error = err })
        elseif result and result.result then
            send_result(request_id, result.result)
        elseif result then
            send_result(request_id, result)
        else
            send_result(request_id, { error = "No result returned from hub" })
        end
    end)
end

--- Async version of access_resource for proxy (uses nice UI)
---@param request_id string Request ID for async response
---@param server_name string Name of the server
---@param uri string Resource URI
---@param params? table Optional parameters including caller context
function M.access_resource(request_id, server_name, uri, params)
    local async = require("plenary.async")

    async.run(function()
        params = params or {}
        local mcphub = require("mcphub")
        local hub = mcphub.get_hub_instance()

        if not hub or not hub:is_ready() then
            send_result(request_id, { error = "Hub is not ready" })
            return
        end

        local caller = params.caller or { type = "proxy" }

        -- Parse and validate params
        local parsed_params = shared.parse_params({
            server_name = server_name,
            uri = uri,
        }, "access_mcp_resource")

        if #parsed_params.errors > 0 then
            send_result(request_id, { error = table.concat(parsed_params.errors, "\n") })
            return
        end

        -- Use the async approval with nice UI!
        local approval = shared.handle_auto_approval_decision(parsed_params)
        if approval.error then
            send_result(request_id, { error = approval.error })
            return
        end

        local result, err = hub:access_resource(server_name, uri, {
            parse_response = false,
            caller = vim.tbl_extend("force", caller, { auto_approve = approval.approve }),
        })

        if err then
            send_result(request_id, { error = err })
        elseif result and result.result then
            send_result(request_id, result.result)
        elseif result then
            send_result(request_id, result)
        else
            send_result(request_id, { error = "No result returned from hub" })
        end
    end)
end

--- Get a prompt via hub.
---@param server_name string Name of the server
---@param prompt_name string Name of the prompt
---@param params table Parameters including arguments and caller context
---@return table Result or error
function M.get_prompt(server_name, prompt_name, params)
    local mcphub = require("mcphub")
    local hub = mcphub.get_hub_instance()

    if not hub or not hub:is_ready() then
        return { error = "Hub is not ready" }
    end

    local arguments = params.arguments or {}
    local caller = params.caller or { type = "proxy" }

    local result, err = hub:get_prompt(server_name, prompt_name, arguments, {
        parse_response = false,
        caller = caller,
    })

    if err then
        return { error = err }
    elseif result and result.result then
        return result.result
    elseif result then
        return result
    end

    return { error = "No result returned from hub" }
end

return M
