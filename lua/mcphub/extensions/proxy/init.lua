local M = {}

local shared = require("mcphub.extensions.shared")

--- Synchronous approval check for RPC context (can't use async UI)
--- Uses vim.schedule + vim.wait to show dialog in main loop while blocking RPC
---@param parsed_params table
---@return {error?: string, approve: boolean}
local function handle_approval_sync(parsed_params)
    local State = require("mcphub.state")

    local auto_approve = State.config.auto_approve or false
    local status = { approve = false, error = nil }

    -- Check global auto_approve config
    if type(auto_approve) == "function" then
        local ok, res = pcall(auto_approve, parsed_params)
        if not ok or type(res) == "string" then
            status = { approve = false, error = res }
        elseif type(res) == "boolean" then
            status = { approve = res, error = nil }
        end
    elseif type(auto_approve) == "boolean" then
        status = { approve = auto_approve, error = nil }
    end

    -- Check server-level autoApprove
    if parsed_params.is_auto_approved_in_server then
        status = { approve = true, error = nil }
    end

    if status.error then
        return { error = status.error, approve = false }
    end

    -- If not auto-approved and needs confirmation, show dialog via vim.schedule
    if status.approve == false and parsed_params.needs_confirmation_window then
        local is_tool = parsed_params.action == "use_mcp_tool"
        local msg = is_tool
                and string.format("Allow tool '%s' on server '%s'?", parsed_params.tool_name, parsed_params.server_name)
            or string.format("Allow access to '%s' on server '%s'?", parsed_params.uri, parsed_params.server_name)

        -- Use vim.schedule to run confirm in main loop, then wait for result
        local result = nil
        local done = false

        vim.schedule(function()
            local choice = vim.fn.confirm(msg, "&Yes\n&No", 2)
            result = choice == 1
            done = true
        end)

        -- Wait for the scheduled function to complete (timeout after 60 seconds)
        vim.wait(60000, function()
            return done
        end, 50)

        if not done then
            return { error = "Approval timeout", approve = false }
        end

        return { error = not result and "User cancelled the operation" or nil, approve = result }
    end

    return status
end

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
        alwaysAllow = true,
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

--- Call a tool via hub.
---@param server_name string Name of the server
---@param tool_name string Name of the tool
---@param params table Parameters including arguments and caller context
---@return table Result or error
function M.call_tool(server_name, tool_name, params)
    local mcphub = require("mcphub")
    local hub = mcphub.get_hub_instance()

    if not hub or not hub:is_ready() then
        return { error = "Hub is not ready" }
    end

    local arguments = params.arguments or {}
    local caller = params.caller or { type = "proxy" }

    -- Handle approval flow (synchronous version for RPC context)
    local parsed_params = shared.parse_params({
        server_name = server_name,
        tool_name = tool_name,
        tool_input = arguments,
    }, "use_mcp_tool")

    if #parsed_params.errors > 0 then
        return { error = table.concat(parsed_params.errors, "\n") }
    end

    local approval = handle_approval_sync(parsed_params)
    if approval.error then
        return { error = approval.error }
    end

    local result, err = hub:call_tool(server_name, tool_name, arguments, {
        parse_response = false,
        caller = vim.tbl_extend("force", caller, { auto_approve = approval.approve }),
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

--- Access a resource via hub.
---@param server_name string Name of the server
---@param uri string Resource URI
---@param params? table Optional parameters including caller context
---@return table Result or error
function M.access_resource(server_name, uri, params)
    params = params or {}
    local mcphub = require("mcphub")
    local hub = mcphub.get_hub_instance()

    if not hub or not hub:is_ready() then
        return { error = "Hub is not ready" }
    end

    local caller = params.caller or { type = "proxy" }

    -- Handle approval flow (same as codecompanion/avante)
    local parsed_params = shared.parse_params({
        server_name = server_name,
        uri = uri,
    }, "access_mcp_resource")

    if #parsed_params.errors > 0 then
        return { error = table.concat(parsed_params.errors, "\n") }
    end

    local approval = handle_approval_sync(parsed_params)
    if approval.error then
        return { error = approval.error }
    end

    local result, err = hub:access_resource(server_name, uri, {
        parse_response = false,
        caller = vim.tbl_extend("force", caller, { auto_approve = approval.approve }),
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
