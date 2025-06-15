local M = {}
local async = require("plenary.async")
local shared = require("mcphub.extensions.shared")

-- Core MCP tool execution logic
function M.execute_mcp_tool(params, agent, output_handler, context)
    context = context or {}
    ---@diagnostic disable-next-line: missing-parameter
    async.run(function()
        -- Reuse existing validation logic
        local parsed_params = shared.parse_params(params, params.action)
        if #parsed_params.errors > 0 then
            return output_handler({
                status = "error",
                data = table.concat(parsed_params.errors, "\n"),
            })
        end

        -- Check both global and server-specific auto-approval
        local auto_approve = (vim.g.mcphub_auto_approve == true)
            or (vim.g.codecompanion_auto_tool_mode == true)
            or parsed_params.should_auto_approve

        if not auto_approve then
            local confirmed = shared.show_mcp_tool_prompt(parsed_params)
            if not confirmed then
                local tool_display_name = context.tool_display_name or parsed_params.action
                return output_handler({
                    status = "error",
                    data = string.format("I have rejected the `%s` tool call.", tool_display_name),
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

        -- Call appropriate hub method
        if parsed_params.action == "access_mcp_resource" then
            hub:access_resource(parsed_params.server_name, parsed_params.uri, {
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
        elseif parsed_params.action == "use_mcp_tool" then
            hub:call_tool(parsed_params.server_name, parsed_params.tool_name, parsed_params.arguments, {
                caller = {
                    type = "codecompanion",
                    codecompanion = agent,
                },
                parse_response = true,
                callback = function(res, err)
                    if err or not res then
                        output_handler({ status = "error", data = tostring(err) or "No response from call tool" })
                    elseif res.error then
                        output_handler({ status = "error", data = res.error })
                    else
                        output_handler({ status = "success", data = res })
                    end
                end,
            })
        else
            return output_handler({
                status = "error",
                data = "Invalid action type: " .. parsed_params.action,
            })
        end
    end)
end

-- Helper function for tool output formatting
local function add_tool_output(
    display_name,
    tool,
    chat,
    llm_msg,
    is_error,
    has_function_calling,
    opts,
    user_msg,
    images
)
    local config = require("codecompanion.config")
    local helpers = require("codecompanion.strategies.chat.helpers")
    local show_result_in_chat = opts.show_result_in_chat == true
    local text = llm_msg

    if has_function_calling then
        chat:add_tool_output(
            tool,
            text,
            (user_msg or show_result_in_chat or is_error) and (user_msg or text)
                or string.format("**`%s` Tool**: Successfully finished", display_name)
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
                content = string.format("I've shared the result of the `%s` tool with you.\n", display_name),
            })
        end
    end
end

---@param display_name string The display name for the tool (could be action_name or individual tool name)
---@param has_function_calling boolean
---@param opts MCPHubCodeCompanionConfig
---@return {error: function, success: function}
function M.create_output_handlers(display_name, has_function_calling, opts)
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
%s
````
]],
                display_name,
                stderr
            )
            add_tool_output(display_name, self, agent.chat, err_msg, true, has_function_calling, opts, nil, {})
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
                    display_name,
                    result.text
                )
            end

            if result.images and #result.images > 0 then
                for _, image in ipairs(result.images) do
                    local cached_file_path = image_cache.save_image(image.data, image.mimeType)
                    local id = cached_file_path
                    table.insert(images, {
                        id = id,
                        base64 = image.data,
                        mimetype = image.mimeType,
                        cached_file_path = cached_file_path,
                    })
                end

                if not to_llm then
                    to_llm = string.format(
                        [[**`%s` Tool**: Returned the following:
````
%s
````]],
                        display_name,
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

            local fallback_to_llm = string.format("**`%s` Tool**: Completed with no output", display_name)
            if opts.show_result_in_chat == false and not to_user then
                to_user = string.format("**`%s` Tool**: Successfully finished", display_name)
            end
            add_tool_output(
                display_name,
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

return M
