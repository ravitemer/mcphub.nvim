local M = {}
local NuiLine = require("mcphub.utils.nuiline")
local Text = require("mcphub.utils.text")
local ui_utils = require("mcphub.utils.ui")

---@alias MCPCallParams {errors: string[], action: MCPHubToolType, server_name: string, tool_name: string, uri: string, arguments: table}

---@param params {server_name: string, tool_name: string, uri: string, tool_input: table | string}
---@param action_name MCPHubToolType
---@return MCPCallParams
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
        uri = uri or "nil",
        arguments = arguments or {},
    }
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
            vim.notify("cancel")
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

---Add slash commands to Avante for all mcp servers
---@param enabled boolean
function M.setup_avante_slash_commands(enabled)
    if not enabled then
        return
    end

    local mcphub = require("mcphub")
    --setup event listners to update variables, tools etc
    mcphub.on({ "servers_updated", "prompt_list_changed" }, function(_)
        local hub = mcphub.get_hub_instance()
        if not hub then
            return
        end
        local prompts = hub:get_prompts()
        local ok, config = pcall(require, "avante.config")
        if not ok then
            return
        end

        local slash_commands = config.slash_commands or {}
        -- remove existing mcp slash commands that start with mcp so that when user disables a server, those prompts are removed
        for i, value in ipairs(slash_commands) do
            local id = value.name or ""
            if id:sub(1, 3) == "mcp" then
                slash_commands[i] = nil
            end
        end
        --add all the current prompts
        for _, prompt in ipairs(prompts) do
            local server_name = prompt.server_name
            local prompt_name = prompt.name or ""
            local description = prompt.description or ""
            local arguments = prompt.arguments or {}
            if type(description) == "function" then
                local desc_ok, desc = pcall(description, prompt)
                if desc_ok then
                    description = desc or ""
                else
                    description = "Error in description function: " .. (desc or "")
                end
            end
            if type(arguments) == "function" then
                local args_ok, args = pcall(arguments, prompt)
                if args_ok then
                    arguments = args or {}
                else
                    vim.notify("Error in arguments function: " .. (args or ""), vim.log.levels.ERROR)
                    arguments = {}
                end
            end
            --remove new lines
            description = description:gsub("\n", " ")

            description = prompt_name .. " (" .. description .. ")"
            local slash_command = {
                name = "mcp:" .. server_name .. ":" .. prompt_name,
                description = description,
                callback = function(sidebar, args, cb)
                    M.collect_arguments(arguments, function(values)
                        local response, err = hub:get_prompt(server_name, prompt_name, values, {
                            caller = {
                                type = "avante",
                                avante = sidebar,
                                meta = {
                                    is_within_slash_command = true,
                                },
                            },
                            parse_response = true,
                        })
                        if not response then
                            if err then
                                vim.notify("Error in slash command: " .. err, vim.log.levels.ERROR)
                                vim.notify("Prompt cancelled", vim.log.levels.INFO)
                            end
                            return
                        end
                        local messages = response.messages or {}
                        local text_messages = {}
                        for i, message in ipairs(messages) do
                            local output = message.output
                            if output.text and output.text ~= "" then
                                if i == #messages and message.role == "user" then
                                    sidebar:set_input_value(output.text)
                                else
                                    table.insert(text_messages, {
                                        role = message.role,
                                        content = output.text,
                                    })
                                end
                            end
                        end
                        sidebar:add_chat_history(text_messages, { visible = true })
                        vim.notify(
                            string.format(
                                "%s message%s added successfully",
                                #text_messages,
                                #text_messages == 1 and "" or "s"
                            ),
                            vim.log.levels.INFO
                        )
                        if cb then
                            cb()
                        end
                    end)
                end,
            }
            table.insert(slash_commands, slash_command)
        end
    end)
end

---Create the confirmation prompt for mcp tool
---@param params MCPCallParams
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

---@param params MCPCallParams
---@return boolean, boolean
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
return M
