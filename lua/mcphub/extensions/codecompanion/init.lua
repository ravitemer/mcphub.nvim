--[[
*MCP Servers Tool adapted for function calling*
This tool can be used to call tools and resources from the MCP Servers.
--]]
local M = {}

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
                        description = "Input object for the tool call",
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

function M.create_tools()
    local codecompanion = require("codecompanion")
    local has_function_calling = codecompanion.has("function-calling")
    -- vim.notify("codecompanion has function-calling: " .. tostring(has_function_calling))
    local tools = {
        groups = {
            mcp = {
                description = "MCP Servers Tool",
                system_prompt = function(_)
                    local hub = require("mcphub").get_hub_instance()
                    if not hub then
                        vim.notify("MCP Hub is not initialized", vim.log.levels.WARN)
                        return ""
                    end
                    local prompt = ""
                    if not has_function_calling then
                        local xml_tool = require("mcphub.extensions.codecompanion.xml_tool")
                        prompt = xml_tool.system_prompt(hub)
                    end
                    prompt = prompt .. hub:get_active_servers_prompt()
                    return prompt
                end,
                tools = {},
            },
        },
    }
    local utils = require("mcphub.extensions.codecompanion.utils")
    for action_name, schema in pairs(tool_schemas) do
        tools[action_name] = {
            description = string.format("Call tools and resources from the MCP Servers."),
            callback = {
                name = action_name,
                cmds = { utils.create_handler(action_name, has_function_calling) },
                system_prompt = function()
                    return ""
                end,
                output = utils.create_output_handlers(action_name, has_function_calling),
                --for xml version we are not using schema anywhere so, no issue if we use function schema for xml also
                schema = schema,
            },
        }
        table.insert(tools.groups.mcp.tools, action_name)
    end
    return tools
end

return M
