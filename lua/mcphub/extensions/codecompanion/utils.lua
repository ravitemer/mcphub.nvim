local M = {}
local State = require("mcphub.state")
local config = require("codecompanion.config")
local log = require("mcphub.utils.log")
local shared = require("mcphub.extensions.shared")

function M.create_handler(action_name, has_function_calling)
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
local function add_tool_output(action_name, tool, chat, llm_msg, is_error, has_function_calling)
    local show_result_in_chat = State.config.extensions.codecompanion.show_result_in_chat == true
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

function M.create_output_handlers(action_name, has_function_calling)
    return {
        error = function(self, agent, cmd, stderr)
            local stderr = has_function_calling and (stderr[1] or "") or cmd[1]
            agent = has_function_calling and agent or self
            if type(stderr) == "table" then
                stderr = vim.inspect(stderr)
            end
            local err_msg = string.format(
                [[ERROR: The `%s` call failed with the following error:
<error>
%s
</error>
]],
                action_name,
                stderr
            )
            add_tool_output(action_name, self, agent.chat, err_msg, true, has_function_calling)
        end,
        success = function(self, agent, cmd, stdout)
            local result = has_function_calling and stdout[1] or cmd[1]
            agent = has_function_calling and agent or self
            -- Show text content if present
            if result.text and result.text ~= "" then
                local to_llm = string.format(
                    [[The `%s` call returned the following text:
%s]],
                    action_name,
                    result.text
                )
                add_tool_output(action_name, self, agent.chat, to_llm, false, has_function_calling)
            end
            -- TODO: Add image support when codecompanion supports it
        end,
    }
end

return M
