local M = {}
local NuiLine = require("mcphub.utils.nuiline")
local State = require("mcphub.state")
local Text = require("mcphub.utils.text")
local native = require("mcphub.native")
local ui_utils = require("mcphub.utils.ui")

---@class MCPHub.ParsedParams
---@field errors string[] List of errors encountered during parsing
---@field action MCPHub.ActionType Action type, either "use_mcp_tool" or "access_mcp_resource"
---@field server_name string Name of the server to call the tool/resource on
---@field tool_name string Name of the tool to call (nil for resources)
---@field arguments table Input arguments for the tool call (empty table for resources)
---@field uri string URI of the resource to access (nil for tools)
---@field is_auto_approved_in_server boolean Whether the tool autoApproved in the servers.json
---@field needs_confirmation_window boolean Whether the tool call needs a confirmation window

---@class MCPHub.ToolCallArgs
---@field server_name string Name of the server to call the tool on.
---@field tool_name string Name of the tool to call.
---@field tool_input table | string Input for the tool call. Must be an object for `use_mcp_tool` action.

---@class MCPHub.ResourceAccessArgs
---@field server_name string Name of the server to call the resource on.
---@field uri string URI of the resource to access.

---@param server_name string Name of the server to check
---@param tool_name string Name of the tool to check
---@return boolean Whether the tool is auto-approved in the server
function M.is_auto_approved_in_server(server_name, tool_name)
    local is_native = native.is_native_server(server_name)
    local server_config = is_native and State.native_servers_config[server_name] or State.servers_config[server_name]
    if not server_config then
        return false
    end
    local auto_approve = server_config.autoApprove
    if not auto_approve then
        return false
    end
    -- If autoApprove is true, approve everything for this server
    if auto_approve == true then
        return true
    end
    -- If autoApprove is an array, check if tool is in the list
    if type(auto_approve) == "table" and vim.islist(auto_approve) then
        return vim.tbl_contains(auto_approve, tool_name)
    end
    return false
end

---@param params MCPHub.ToolCallArgs | MCPHub.ResourceAccessArgs
---@param action_name MCPHub.ActionType
---@return MCPHub.ParsedParams
function M.parse_params(params, action_name)
    params = params or {}

    local server_name = params.server_name
    local tool_name = params.tool_name
    local uri = params.uri
    local arguments = params.tool_input or {}
    if type(arguments) == "string" then
        local json_ok, decode_result = pcall(vim.fn.json_decode, arguments or "{}")
        if json_ok then
            arguments = decode_result or {}
        else
            arguments = {}
        end
    end
    local errors = {}
    if not vim.tbl_contains({ "use_mcp_tool", "access_mcp_resource" }, action_name) then
        table.insert(errors, "Action must be one of `use_mcp_tool` or `access_mcp_resource`")
    end
    if not server_name then
        table.insert(errors, "server_name is required")
    end
    if action_name == "use_mcp_tool" and not tool_name then
        table.insert(errors, "tool_name is required")
    end
    if action_name == "use_mcp_tool" and type(arguments) ~= "table" then
        table.insert(errors, "tool_input must be an object")
    end

    if action_name == "access_mcp_resource" and not uri then
        table.insert(errors, "uri is required")
    end

    return {
        errors = errors,
        action = action_name or "nil",
        server_name = server_name or "nil",
        tool_name = tool_name or "nil",
        arguments = arguments or {},
        uri = uri or "nil",
        needs_confirmation_window = M.needs_confirmation_window(server_name, tool_name),
        is_auto_approved_in_server = M.is_auto_approved_in_server(server_name, tool_name),
    }
end

--- For some built-in tools, we already show interactive diffs, before confirmation.
---@param server_name string Name of the server
---@param tool_name string Name of the tool to check
function M.needs_confirmation_window(server_name, tool_name)
    local server = native.is_native_server(server_name)
    if not server then
        return true
    end
    for _, tool in ipairs(server.capabilities.tools) do
        if tool.name == tool_name and tool.needs_confirmation_window == false then
            return false
        end
    end
    return true
end
---@param arguments MCPPromptArgument[]
---@param callback fun(values: string[])
function M.collect_arguments(arguments, callback)
    local values = {}
    local should_proceed = true

    local function collect_input(index)
        if index > #arguments and should_proceed then
            callback(values)
            return
        end

        local arg = arguments[index]
        local title = string.format("%s %s", arg.name, arg.required and "(required)" or "")
        local default = arg.default or ""

        local function submit_input(input)
            if arg.required and (input == nil or input == "") then
                vim.notify("Value for " .. arg.name .. " is required", vim.log.levels.ERROR)
                should_proceed = false
                return
            end

            values[arg.name] = input
            collect_input(index + 1)
        end

        local function cancel_input()
            if arg.required then
                vim.notify("Value for " .. arg.name .. " is required", vim.log.levels.ERROR)
                should_proceed = false
                return
            end
            values[arg.name] = nil
            collect_input(index + 1)
        end
        ui_utils.multiline_input(title, default, submit_input, { on_cancel = cancel_input })
    end

    if #arguments > 0 then
        vim.defer_fn(function()
            collect_input(1)
        end, 0)
    else
        callback(values)
    end
end

---Create the confirmation prompt for mcp tool
---@param params MCPHub.ParsedParams
---@return string
function M.get_mcp_tool_prompt(params)
    local action_name = params.action
    local server_name = params.server_name
    local tool_name = params.tool_name
    local uri = params.uri
    local arguments = params.arguments or {}

    local args = ""
    for k, v in pairs(arguments) do
        args = args .. k .. ":\n "
        if type(v) == "string" then
            local lines = vim.split(v, "\n")
            for _, line in ipairs(lines) do
                args = args .. line .. "\n"
            end
        else
            args = args .. vim.inspect(v) .. "\n"
        end
    end
    local msg = ""
    if action_name == "use_mcp_tool" then
        msg = string.format(
            [[Do you want to run the `%s` tool on the `%s` mcp server with arguments:
%s]],
            tool_name,
            server_name,
            args
        )
    elseif action_name == "access_mcp_resource" then
        msg = string.format("Do you want to access the resource `%s` on the `%s` server?", uri, server_name)
    end
    return msg
end

---@param params MCPHub.ParsedParams
---@return boolean confirmed
---@return boolean cancelled
function M.show_mcp_tool_prompt(params)
    local action_name = params.action
    local server_name = params.server_name
    local tool_name = params.tool_name
    local uri = params.uri
    local arguments = params.arguments or {}

    local lines = {}
    local is_tool = action_name == "use_mcp_tool"

    -- Header as a question
    local header_line = NuiLine()
    header_line:append(Text.icons.event, Text.highlights.warn)
    header_line:append(" Do you want to ", Text.highlights.text)
    if is_tool then
        header_line:append("call ", Text.highlights.text)
        header_line:append(tool_name, Text.highlights.warn_italic)
    else
        header_line:append("access ", Text.highlights.text)
        header_line:append(uri, Text.highlights.link)
    end
    header_line:append(" on ", Text.highlights.text)
    header_line:append(server_name, Text.highlights.success_italic)
    header_line:append("?", Text.highlights.text)
    table.insert(lines, header_line)

    -- Parameters section
    if is_tool and next(arguments) then
        table.insert(lines, NuiLine():append(""))

        for key, value in pairs(arguments) do
            -- Parameter name
            local param_name_line = NuiLine()
            param_name_line:append(Text.icons.param, Text.highlights.info)
            param_name_line:append(" " .. key .. ":", Text.highlights.json_property)
            table.insert(lines, param_name_line)

            -- Parameter value
            local function add_value_lines(val)
                if type(val) == "string" then
                    local value_lines = val:find("\n") and vim.split(val, "\n", { plain = true })
                        or { '"' .. val .. '"' }
                    for _, line in ipairs(value_lines) do
                        local value_line = NuiLine()
                        value_line:append("    " .. line, Text.highlights.json_string)
                        table.insert(lines, value_line)
                    end
                elseif type(val) == "boolean" then
                    local value_line = NuiLine()
                    value_line:append("    " .. tostring(val), Text.highlights.json_boolean)
                    table.insert(lines, value_line)
                elseif type(val) == "number" then
                    local value_line = NuiLine()
                    value_line:append("    " .. tostring(val), Text.highlights.json_number)
                    table.insert(lines, value_line)
                else
                    for _, line in ipairs(vim.split(vim.inspect(val), "\n", { plain = true })) do
                        local value_line = NuiLine()
                        value_line:append("    " .. line, Text.highlights.muted)
                        table.insert(lines, value_line)
                    end
                end
            end

            add_value_lines(value)
            table.insert(lines, NuiLine():append(""))
        end
    end

    return require("mcphub.utils.ui").confirm(lines, {
        min_width = 70,
        max_width = 100,
    })
end

---@param parsed_params MCPHub.ParsedParams
---@return {error?:string, approve:boolean}
function M.handle_auto_approval_decision(parsed_params)
    local auto_approve = State.config.auto_approve or false
    local status = { approve = false, error = nil }
    --- If user has a custom function that decides whether to auto-approve
    --- call that with params + saved autoApprove state as is_auto_approved_in_server field
    if type(auto_approve) == "function" then
        local ok, res = pcall(auto_approve, parsed_params)
        if not ok or type(res) == "string" then
            --- If auto_approve function throws an error, or returns a string, treat it as an error
            status = { approve = false, error = res }
        elseif type(res) == "boolean" then
            --- If auto_approve function returns a boolean, use that as the decision
            status = { approve = res, error = nil }
        end
    elseif type(auto_approve) == "boolean" then
        status = { approve = auto_approve, error = nil }
    end

    -- Check if auto-approval is enabled in servers.json
    if parsed_params.is_auto_approved_in_server then
        status = { approve = true, error = nil }
    end

    if status.error then
        return { error = status.error or "Something went wrong with auto-approval", approve = false }
    end

    if status.approve == false and parsed_params.needs_confirmation_window then
        local confirmed, _ = M.show_mcp_tool_prompt(parsed_params)
        return { error = not confirmed and "User cancelled the operation", approve = confirmed }
    end
    return status
end

return M
