--[[
*MCP Servers Tool adapted for function calling*
This tool can be used to call tools and resources from the MCP Servers.
--]]
--
--
--Add this to your codecompanion config: and use @mcp. (individual @use_mcp_tool or @access_mcp_resource doesn't work as the active servers prompt is not attached to these)
--
-- tools = vim.tbl_deep_extend("force", {
--  -- your tools config
--   }, require("mcphub.extensions.codecompanion").make_tools()),
--
local State = require("mcphub.state")
local config = require("codecompanion.config")
local M = {}

local function parse_params(params, action_name)
    params = params or {}
    local server_name = params.server_name
    local tool_name = params.tool_name
    local uri = params.uri
    local arguments = params.tool_input or {}
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
        table.insert(errors, "parameters must be an object")
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

local function run_action(action_name)
    return function(agent, args, _, output_handler)
        local params = parse_params(args, action_name)
        if #params.errors > 0 then
            return {
                status = "error",
                data = table.concat(params.errors, "\n"),
            }
        end

        local auto_approve = (vim.g.mcphub_auto_approve == true) or (vim.g.codecompanion_auto_tool_mode == true)
        if not auto_approve then
            local utils = require("mcphub.extensions.utils")
            local confirmed = utils.show_mcp_tool_prompt(params)
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

local function output_handlers(action_name)
    return {
        error = function(agent, _, stderr)
            stderr = stderr[1] or ""
            if type(stderr) == "table" then
                stderr = vim.inspect(stderr)
            end
            agent.chat:add_buf_message({
                role = config.constants.USER_ROLE,
                content = string.format(
                    [[ERROR: The `%s` call failed with the following error:
<error>
%s
</error>
]],
                    action_name,
                    stderr
                ),
            }, {
                visible = false,
            })
        end,
        success = function(agent, _, output)
            local result = output[1]
            -- Show text content if present
            -- TODO: add messages with role = `tool` when supported
            if result.text and result.text ~= "" then
                if State.config.extensions.codecompanion.show_result_in_chat == true then
                    agent.chat:add_buf_message({
                        role = config.constants.USER_ROLE,
                        content = string.format(
                            [[The `%s` call returned the following text:
%s]],
                            action_name,
                            result.text
                        ),
                    })
                else
                    agent.chat:add_message({
                        role = config.constants.USER_ROLE,
                        content = string.format(
                            [[The `%s` call returned the following text:
%s]],
                            action_name,
                            result.text
                        ),
                    })
                    agent.chat:add_buf_message({
                        role = config.constants.USER_ROLE,
                        content = "I've shared the result of the `mcp` tool with you.\n",
                    })
                end
            end
            -- Show image content if present
            -- if result.images and #result.images > 0 then
            -- TODO: Add image support when codecompanion supports it
            -- self.chat:add_message({
            --     role = config.constants.USER_ROLE,
            --     content = vim.tbl_map(function(image)
            --         return {
            --             type = "image",
            --             base64 = string.format("data:%s;base64,%s", image.mimeType, image.data),
            --         }
            --     end, result.images),
            -- }, { visible = false })
            -- end
        end,
    }
end

local tool_schemas = {
    access_mcp_resource = {
        type = "function",
        ["function"] = {
            name = "access_mcp_resource",
            description = "Get resources on MCP servers.",
            parameters = {
                type = "object",
                properties = {
                    server_name = {
                        description = "Name of the server to call the resource on. Must be from one of the available servers.",
                        type = "string",
                    },
                    uri = {
                        description = "URI of the resource to access.",
                        type = "string",
                    },
                },
                required = {
                    "server_name",
                    "uri",
                },
                additionalProperties = false,
            },
            strict = true,
        },
    },
    use_mcp_tool = {
        type = "function",
        ["function"] = {
            name = "use_mcp_tool",
            description = "Calls tools on MCP servers.",
            parameters = {
                type = "object",
                properties = {
                    server_name = {
                        description = "Name of the server to call the tool on. Must be from one of the available servers.",
                        type = "string",
                    },
                    tool_name = {
                        description = "Name of the tool to call.",
                        type = "string",
                    },
                    tool_input = {
                        description = "Input for the tool call",
                        type = "object",
                    },
                },
                required = {
                    "server_name",
                    "tool_name",
                    "tool_input",
                },
                additionalProperties = false,
            },
            strict = true,
        },
    },
}

function M.make_tools()
    local tools = {
        groups = {
            mcp = {
                description = "MCP Servers Tool",
                system_prompt = function(_)
                    local hub = require("mcphub").get_hub_instance()
                    local prompt = hub:get_active_servers_prompt() -- generates prompt from currently running mcp servers
                    return prompt
                end,
                tools = {},
            },
        },
    }
    for action_name, schema in pairs(tool_schemas) do
        tools[action_name] = {
            description = string.format("Call tools and resources from the MCP Servers."),
            callback = {
                name = action_name,
                cmds = { run_action(action_name) },
                output = output_handlers(action_name),
                schema = schema,
            },
        }
        table.insert(tools.groups.mcp.tools, action_name)
    end
    return tools
end

return M
