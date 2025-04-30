local M = {}
local shared = require("mcphub.extensions.shared")

function M.create_handler(action_name, has_function_calling, opts)
    return function(agent, args, _, output_handler)
        local params = shared.parse_params(args, action_name)
        if #params.errors > 0 then
            return {
                status = "error",
                data = table.concat(params.errors, "\n"),
            }
        end

        local auto_approve = (vim.g.mcphub_auto_approve == true) or (vim.g.codecompanion_auto_tool_mode == true)
        if not auto_approve then
            local confirmed = shared.show_mcp_tool_prompt(params)
            if not confirmed then
                return {
                    status = "error",
                    data = string.format("I have rejected the `%s` action on mcp tool.", params.action),
                }
            end
        end
        local hub = require("mcphub").get_hub_instance()
        if params.action == "use_mcp_tool" then
            --use async call_tool method
            hub:call_tool(params.server_name, params.tool_name, params.arguments, {
                caller = {
                    type = "codecompanion",
                    codecompanion = agent,
                },
                parse_response = true,
                callback = function(res, err)
                    if err or not res then
                        output_handler({ status = "error", data = tostring(err) or "No response from call tool" })
                    elseif res then
                        output_handler({ status = "success", data = res })
                    end
                end,
            })
        elseif params.action == "access_mcp_resource" then
            -- use async access_resource method
            hub:access_resource(params.server_name, params.uri, {
                caller = {
                    type = "codecompanion",
                    codecompanion = agent,
                },
                parse_response = true,
                callback = function(res, err)
                    if err or not res then
                        output_handler({
                            status = "error",
                            data = tostring(err) or "No response from access resource",
                        })
                    elseif res then
                        output_handler({ status = "success", data = res })
                    end
                end,
            })
        else
            return {
                status = "error",
                data = "Invalid action type" .. params.action,
            }
        end
    end
end

local function replace_headers(text)
    local lines = vim.split(text, "\n")
    for i, line in ipairs(lines) do
        -- if line starts with #, ##, ###, #### etc replace them with >,>> ,>>> etc
        lines[i] = line:gsub("^(#+)", function(hash)
            local level = #hash
            return string.rep(">", level)
        end)
    end
    return table.concat(lines, "\n")
end
local function add_tool_output(action_name, tool, chat, llm_msg, is_error, has_function_calling, opts)
    local config = require("codecompanion.config")
    local show_result_in_chat = opts.show_result_in_chat == true
    local text = show_result_in_chat and replace_headers(llm_msg) or llm_msg
    if has_function_calling then
        chat:add_tool_output(tool, text, (show_result_in_chat or is_error) and text or "Tool result shared")
    else
        if show_result_in_chat or is_error then
            chat:add_buf_message({
                role = config.constants.USER_ROLE,
                content = text,
            })
        else
            chat:add_message({
                role = config.constants.USER_ROLE,
                content = text,
            })
            chat:add_buf_message({
                role = config.constants.USER_ROLE,
                content = string.format("I've shared the result of the `%s` tool with you.\n", action_name),
            })
        end
    end
end

function M.create_output_handlers(action_name, has_function_calling, opts)
    return {
        error = function(self, agent, cmd, stderr)
            local stderr = has_function_calling and (stderr[1] or "") or cmd[1]
            agent = has_function_calling and agent or self
            if type(stderr) == "table" then
                stderr = vim.inspect(stderr)
            end
            local err_msg = string.format(
                [[**`%s` Tool**: Failed with the following error:

```                
<error>
%s
</error>
```
]],
                action_name,
                stderr
            )
            add_tool_output(action_name, self, agent.chat, err_msg, true, has_function_calling, opts)
        end,
        success = function(self, agent, cmd, stdout)
            local result = has_function_calling and stdout[1] or cmd[1]
            agent = has_function_calling and agent or self
            -- Show text content if present
            -- TODO: add messages with role = `tool` when supported
            if result.text and result.text ~= "" then
                local to_llm = string.format(
                    [[**`%s` Tool**: Returned the following:

```
%s
```]],
                    action_name,
                    result.text
                )
                add_tool_output(action_name, self, agent.chat, to_llm, false, has_function_calling, opts)
            end
            -- TODO: Add image support when codecompanion supports it
        end,
    }
end

function M.setup_codecompanion_variables(opts)
    if not opts.make_vars then
        return
    end
    local mcphub = require("mcphub")
    --setup event listners to update variables, tools etc
    mcphub.on({ "servers_updated", "resource_list_changed" }, function(_)
        local hub = mcphub.get_hub_instance()
        if not hub then
            return
        end
        local resources = hub:get_resources()
        local ok, config = pcall(require, "codecompanion.config")
        if not ok then
            return
        end

        local cc_variables = config.strategies.chat.variables
        -- remove existing mcp variables that start with mcp
        for key, value in pairs(cc_variables) do
            local id = value.id or ""
            if id:sub(1, 3) == "mcp" then
                cc_variables[key] = nil
            end
        end
        for _, resource in ipairs(resources) do
            local server_name = resource.server_name
            local uri = resource.uri
            local resource_name = resource.name or uri
            local description = resource.description or ""
            if type(description) == "function" then
                local ok, desc = pcall(description, resource)
                if ok then
                    description = desc or ""
                else
                    description = "Error in description function: " .. (desc or "")
                end
            end
            --remove new lines
            description = description:gsub("\n", " ")

            description = resource_name .. " (" .. description .. ")"
            cc_variables[uri] = {
                id = "mcp" .. server_name .. uri,
                description = description,
                callback = function(self)
                    -- this is sync and will block the UI (can't use async in variables yet)
                    local response = hub:access_resource(server_name, uri, {
                        caller = {
                            type = "codecompanion",
                            codecompanion = self,
                            meta = {
                                is_within_variable = true,
                            },
                        },
                        parse_response = true,
                    })
                    return response and response.text
                end,
            }
        end
    end)
end

function M.setup_codecompanion_slash_commands(opts)
    if not opts.make_slash_commands then
        return
    end

    local mcphub = require("mcphub")
    local config = require("codecompanion.config")
    --setup event listners to update variables, tools etc
    mcphub.on({ "servers_updated", "prompt_list_changed" }, function(_)
        local hub = mcphub.get_hub_instance()
        if not hub then
            return
        end
        local prompts = hub:get_prompts()
        local slash_commands = config.strategies.chat.slash_commands
        -- remove existing mcp slash commands that start with mcp
        for key, value in pairs(slash_commands) do
            local id = value.id or ""
            if id:sub(1, 3) == "mcp" then
                slash_commands[key] = nil
            end
        end
        for _, prompt in ipairs(prompts) do
            local server_name = prompt.server_name
            local prompt_name = prompt.name or ""
            local description = prompt.description or ""
            local arguments = prompt.arguments or {}
            if type(description) == "function" then
                local ok, desc = pcall(description, prompt)
                if ok then
                    description = desc or ""
                else
                    description = "Error in description function: " .. (desc or "")
                end
            end
            if type(arguments) == "function" then
                local ok, args = pcall(arguments, prompt)
                if ok then
                    arguments = args or {}
                else
                    vim.notify("Error in arguments function: " .. (args or ""), vim.log.levels.ERROR)
                    arguments = {}
                end
            end
            --remove new lines
            description = description:gsub("\n", " ")

            description = prompt_name .. " (" .. description .. ")"
            slash_commands["mcp:" .. prompt_name] = {
                id = "mcp" .. server_name .. prompt_name,
                description = description,
                callback = function(self)
                    shared.collect_arguments(arguments, function(values)
                        -- this is sync and will block the UI (can't use async in slash_commands yet)
                        local response, err = hub:get_prompt(server_name, prompt_name, values, {
                            caller = {
                                type = "codecompanion",
                                codecompanion = self,
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
                        local text_messages = 0
                        for i, message in ipairs(messages) do
                            local output = message.output
                            --TODO: Currently codecompanion only supports text messages
                            if output.text and output.text ~= "" then
                                local mapped_role = message.role == "assistant" and config.constants.LLM_ROLE
                                    or message.role == "system" and config.constants.SYSTEM_ROLE
                                    or config.constants.USER_ROLE
                                text_messages = text_messages + 1
                                -- if last message is from user, add it to the chat buffer
                                if i == #messages and mapped_role == config.constants.USER_ROLE then
                                    self:add_buf_message({
                                        role = mapped_role,
                                        content = output.text,
                                    })
                                else
                                    self:add_message({
                                        role = mapped_role,
                                        content = output.text,
                                    })
                                end
                            end
                        end
                        vim.notify(
                            string.format(
                                "%s message%s added successfully",
                                text_messages,
                                text_messages == 1 and "" or "s"
                            ),
                            vim.log.levels.INFO
                        )
                    end)
                end,
            }
        end
    end)
end

function M.setup_codecompanion_tools(enabled)
    if not enabled then
        return
    end
    --INFO:Individual tools might be an overkill
end

return M
