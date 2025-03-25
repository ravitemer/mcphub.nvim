local M = {}

function M.mcp_tool()
    return {
        name = "mcp",
        description = "The Model Context Protocol (MCP) enables communication with locally running MCP servers that provide additional tools and resources to extend your capabilities. This tool calls mcp tools and resources on the mcp servers.",
        param = {
            type = "table",
            fields = {
                {
                    name = "action",
                    description = "Action to perform: one of `access_mcp_resource` or `use_mcp_tool`",
                    type = "string",
                },
                {
                    name = "server_name",
                    description = "Name of the MCP server",
                    type = "string",
                },
                {
                    name = "uri",
                    description = "URI of the resource to access",
                    type = "string",
                },
                {
                    name = "tool_name",
                    description = "Name of the tool to call",
                    type = "string",
                },
                {
                    name = "arguments",
                    description = "Arguments for the tool",
                    type = "object",
                },
            },
        },
        returns = {
            {
                name = "result",
                description = "Result from the MCP tool",
                type = "string",
            },
            {
                name = "error",
                description = "Error message if the call failed",
                type = "string",
                optional = true,
            },
        },
        func = function(params, on_log, on_complete)
            local hub = require("mcphub").get_hub_instance()
            if not hub then
                return nil, "MCP Hub not initialized"
            end

            if not params.server_name then
                return nil, "server_name is required"
            end
            if params.action == "access_mcp_resource" and not params.uri then
                return nil, "uri is required"
            end

            if params.action == "use_mcp_tool" and not params.tool_name then
                return nil, "tool_name is required"
            end

            local sidebar = require("avante").get()
            if params.action == "access_mcp_resource" then
                hub:access_resource(params.server_name, params.uri, {
                    parse_response = true,
                    caller = {
                        type = "avante",
                        avante = sidebar,
                    },
                    callback = function(result, err)
                        --result has .text and .images [{mimeType, data}]
                        on_complete(result.text, err)
                    end,
                })
            elseif params.action == "use_mcp_tool" then
                hub:call_tool(params.server_name, params.tool_name, params.arguments, {
                    parse_response = true,
                    caller = {
                        type = "avante",
                        avante = sidebar,
                    },
                    callback = function(result, err)
                        on_complete(result.text, err)
                    end,
                })
            else
                return nil, "Invalid action type"
            end
        end,
    }
end

return M
