local M = {}
local async = require("plenary.async")
local shared = require("mcphub.extensions.shared")

---@param action_name MCPHubToolType
---@param has_function_calling boolean
---@param opts MCPHubCodeCompanionConfig
---@return function
function M.create_handler(action_name, has_function_calling, opts)
    return function(agent, args, _, output_handler)
        ---@diagnostic disable-next-line: missing-parameter
        async.run(function()
            local params = shared.parse_params(args, action_name)
            if #params.errors > 0 then
                return output_handler({
                    status = "error",
                    data = table.concat(params.errors, "\n"),
                })
            end

            local auto_approve = (vim.g.mcphub_auto_approve == true)
                or (vim.g.codecompanion_auto_tool_mode == true)
                or params.should_auto_approve
            if not auto_approve then
                local confirmed = shared.show_mcp_tool_prompt(params)
                if not confirmed then
                    return output_handler({
                        status = "error",
                        data = string.format("I have rejected the `%s` action on mcp tool.", params.action),
                    })
                end
            end
            local hub = require("mcphub").get_hub_instance()
            if not hub then
                return output_handler({
                    status = "error",
                    data = "MCP Hub is not ready yet",
                })
            end
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
                            -- throw safely thrown MCP error with isError as well for proper UI display for chat plugins
                            if res.error then
                                output_handler({ status = "error", data = res.error })
                            else
                                output_handler({ status = "success", data = res })
                            end
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
                                data = err and tostring(err) or "No response from access resource",
                            })
                        elseif res then
                            output_handler({ status = "success", data = res })
                        end
                    end,
                })
            else
                return output_handler({
                    status = "error",
                    data = "Invalid action type" .. params.action,
                })
            end
        end)
    end
end

---@param action_name MCPHubToolType
---@param tool table
---@param chat any
---@param llm_msg string
---@param is_error boolean
---@param has_function_calling boolean
---@param opts MCPHubCodeCompanionConfig
---@param user_msg string?
---@param images {id:string, base64: string, mimetype : string, cached_file_path: string| nil}[]
local function add_tool_output(action_name, tool, chat, llm_msg, is_error, has_function_calling, opts, user_msg, images)
    local config = require("codecompanion.config")
    local helpers = require("codecompanion.strategies.chat.helpers")
    local show_result_in_chat = opts.show_result_in_chat == true
    -- local text = show_result_in_chat and replace_headers(llm_msg) or llm_msg
    local text = llm_msg
    if has_function_calling then
        chat:add_tool_output(
            tool,
            text,
            (user_msg or show_result_in_chat or is_error) and (user_msg or text)
                or string.format("**`%s` Tool**: Successfully finished", action_name)
        )
        for _, image in ipairs(images) do
            helpers.add_image(chat, image)
        end
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

---@param action_name MCPHubToolType
---@param has_function_calling boolean
---@param opts MCPHubCodeCompanionConfig
---@return {error: function, success: function}
function M.create_output_handlers(action_name, has_function_calling, opts)
    return {
        error = function(self, agent, cmd, stderr)
            stderr = has_function_calling and (stderr[#stderr] or "") or cmd[#cmd]
            agent = has_function_calling and agent or self
            if type(stderr) == "table" then
                stderr = vim.inspect(stderr)
            end
            local err_msg = string.format(
                [[**`%s` Tool**: Failed with the following error:

````               
<error>
%s
</error>
````
]],
                action_name,
                stderr
            )
            add_tool_output(action_name, self, agent.chat, err_msg, true, has_function_calling, opts, nil, {})
        end,
        success = function(self, agent, cmd, stdout)
            local image_cache = require("mcphub.utils.image_cache")
            ---@type MCPResponseOutput
            local result = has_function_calling and stdout[#stdout] or cmd[#cmd]
            agent = has_function_calling and agent or self
            local to_llm = nil
            local to_user = nil
            local images = {}
            if result.text and result.text ~= "" then
                to_llm = string.format(
                    [[**`%s` Tool**: Returned the following:

````
%s
````]],
                    action_name,
                    result.text
                )
            end
            if result.images and #result.images > 0 then
                ---When the mcp call returns just images, we need to add the tool output
                for _, image in ipairs(result.images) do
                    local cached_file_path = image_cache.save_image(image.data, image.mimeType)

                    -- local id = string.format("mcp-%s", os.time())
                    local id = cached_file_path
                    table.insert(images, {
                        id = id,
                        base64 = image.data,
                        mimetype = image.mimeType,
                        cached_file_path = cached_file_path,
                    })
                end
                --- If there is no text response, add no of images returned
                if not to_llm then
                    to_llm = string.format(
                        [[**`%s` Tool**: Returned the following:
````
%s
````]],
                        action_name,
                        string.format("%d image%s returned", #result.images, #result.images > 1 and "s" or "")
                    )
                end
                to_user = to_llm .. (#images > 0 and string.format("\n\n#### Preview Images\n") or "")
                for _, image in ipairs(images) do
                    local file = image.cached_file_path
                    if file then
                        local file_name = vim.fn.fnamemodify(file, ":t")
                        to_user = to_user .. string.format("\n![%s](%s)\n", file_name, vim.fn.fnameescape(file))
                    else
                        to_user = to_user .. string.format("\n![Image not saved properly](%s)\n", file)
                    end
                end
            end
            local fallback_to_llm = string.format("**`%s` Tool**: Completed with no output", action_name)
            add_tool_output(
                action_name,
                self,
                agent.chat,
                to_llm or fallback_to_llm,
                false,
                has_function_calling,
                opts,
                to_user,
                images
            )
        end,
    }
end

---@param opts MCPHubCodeCompanionConfig
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
            description = description:gsub("\n", " ")

            description = resource_name .. " (" .. description .. ")"
            cc_variables[uri] = {
                id = "mcp" .. server_name .. uri,
                description = description,
                callback = function(self)
                    -- this is sync and will block the UI (can't use async in variables yet)
                    local result = hub:access_resource(server_name, uri, {
                        caller = {
                            type = "codecompanion",
                            codecompanion = self,
                            meta = {
                                is_within_variable = true,
                            },
                        },
                        parse_response = true,
                    })
                    if not result then
                        return string.format("Accessing resource failed: %s", uri)
                    end

                    if result.images and #result.images > 0 then
                        local helpers = require("codecompanion.strategies.chat.helpers")
                        for _, image in ipairs(result.images) do
                            local id = string.format("mcp-%s", os.time())
                            helpers.add_image(self.Chat, {
                                id = id,
                                base64 = image.data,
                                mimetype = image.mimeType,
                            })
                        end
                    end
                    return result.text
                end,
            }
        end
    end)
end

---@param opts MCPHubCodeCompanionConfig
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
            description = description:gsub("\n", " ")
            description = prompt_name .. " (" .. description .. ")"

            local arguments = prompt.arguments or {}
            if type(arguments) == "function" then
                local ok, args = pcall(arguments, prompt)
                if ok then
                    arguments = args or {}
                else
                    vim.notify("Error in arguments function: " .. (args or ""), vim.log.levels.ERROR)
                    arguments = {}
                end
            end

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
                            local mapped_role = message.role == "assistant" and config.constants.LLM_ROLE
                                or message.role == "system" and config.constants.SYSTEM_ROLE
                                or config.constants.USER_ROLE
                            if output.text and output.text ~= "" then
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
                            if output.images and #output.images > 0 then
                                local helpers = require("codecompanion.strategies.chat.helpers")
                                for _, image in ipairs(output.images) do
                                    local id = string.format("mcp-%s", os.time())
                                    helpers.add_image(self, {
                                        id = id,
                                        base64 = image.data,
                                        mimetype = image.mimeType,
                                    }, { role = mapped_role })
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
