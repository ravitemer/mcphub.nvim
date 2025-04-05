--[[
*MCP Servers Tool*
This tool can be used to call tools and resources from the MCP Servers.
--]]
local State = require("mcphub.state")
local config = require("codecompanion.config")

local function parse_params(params)
    params = params or {}
    local action_name = params.action
    local server_name = params.server_name
    local tool_name = params.tool_name
    local uri = params.uri
    local arguments = params.arguments or {}
    local errors = {}
    if not server_name then
        table.insert(errors, "Server name is required")
    end
    if not vim.tbl_contains({ "use_mcp_tool", "access_mcp_resource" }, action_name) then
        table.insert(errors, "Action must be one of `use_mcp_tool` or `access_mcp_resource`")
    end
    if action_name == "use_mcp_tool" and not tool_name then
        table.insert(errors, "Tool name is required")
    end
    if action_name == "access_mcp_resource" and not uri then
        table.insert(errors, "URI is required")
    end
    if type(arguments) ~= "table" then
        table.insert(errors, "Arguments must be an object")
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
---@class CodeCompanion.Tool
local tool_schema = {
    name = "mcp",
    cmds = {
        function(agent, args, _, output_handler)
            local params = parse_params(args)
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
        end,
    },
    schema = {
        type = "function",
        ["function"] = {
            name = "mcp",
            description = "The Model Context Protocol (MCP) enables communication with locally running MCP servers that provide additional tools and resources to extend your capabilities. This tool calls mcp tools and resources on the mcp servers using `use_mcp_tool` and `access_mcp_resource` actions respectively.",
            parameters = {
                type = "object",
                properties = {
                    action = {
                        description = "Action to perform: one of `access_mcp_resource` or `use_mcp_tool`. Must be provided always.",
                        type = "string",
                        enum = {
                            "use_mcp_tool",
                            "access_mcp_resource",
                        },
                    },
                    server_name = {
                        description = "Name of the on the available MCP servers. Must be provided always.",
                        type = "string",
                    },
                    tool_name = {
                        description = "Name of the tool from server_name's available tools to call while using `use_mcp_tool` action. Must be provided when action is `use_mcp_tool`",
                        type = "string",
                    },
                    arguments = {
                        description = "Arguments for the `use_mcp_tool` action based on tool_name's inputSchema. Must be provided when action is `use_mcp_tool`.",
                        type = "object",
                    },
                    uri = {
                        description = "URI of the resource or resourceTemplate to access when using `access_mcp_resource` action. Must be provided when action is `access_mcp_resource`.",
                        type = "string",
                    },
                },
                required = {
                    "action",
                    "server_name",
                },
                additionalProperties = false,
            },
            strict = true,
        },
    },

    system_prompt = function(schema)
        -- get the running hub instance
        local hub = require("mcphub").get_hub_instance()
        return hub:get_active_servers_prompt() -- generates prompt from currently running mcp servers
    end,
    output = {
        error = function(agent, args, stderr)
            local params = parse_params(args)
            local action_name = params.action
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
        success = function(agent, args, output)
            local result = output[1]
            local params = parse_params(args)
            local action_name = params.action
            -- Show text content if present
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
    },
}

return tool_schema
