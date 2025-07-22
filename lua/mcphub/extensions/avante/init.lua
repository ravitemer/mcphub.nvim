---@module "avante"
--[[
*MCP Servers Tool*
This tool can be used to call tools and resources from the MCP Servers.
M.mcp_tool() will return a use_mcp_tool and access_mcp_resource function schemas.

M.use_mcp_tool() will return schema for calling tools on MCP servers.
M.access_mcp_resource() will return schema for accessing resources on MCP servers.
--]]

---@class MCPHub.Extensions.Avante
---@field setup function(config: MCPHub.Extensions.AvanteConfig) Setup slash commands and other configurations for Avante extension
---@field mcp_tool fun(): AvanteLLMTool,AvanteLLMTool
---@field use_mcp_tool AvanteLLMTool
---@field access_mcp_resource AvanteLLMTool

---@class MCPHub.Extensions.Avante
local M = {}

---@type table<MCPHub.ActionType, AvanteLLMTool>
local tool_schemas = {
    use_mcp_tool = {
        name = "use_mcp_tool",
        description = "Calls tools on MCP servers.",
        param = {
            type = "table",
            fields = {
                {
                    name = "server_name",
                    description = "Name of the server to call the tool on. Must be from one of the available servers.",
                    type = "string",
                },
                {
                    name = "tool_name",
                    description = "Name of the tool to call.",
                    type = "string",
                },
                {
                    name = "tool_input",
                    description = "Input for the tool call. Must be a valid JSON object.",
                    type = "object",
                },
            },
        },
        returns = {}, -- Will be added dynamically in mcp_tool()
    },

    access_mcp_resource = {
        name = "access_mcp_resource",
        description = "Get resources on MCP servers.",
        param = {
            type = "table",
            fields = {
                {
                    name = "server_name",
                    description = "Name of the server to call the resource on. Must be from one of the available servers.",
                    type = "string",
                },
                {
                    name = "uri",
                    description = "URI of the resource to access.",
                    type = "string",
                },
            },
        },
        returns = {}, -- Will be added dynamically in mcp_tool()
    },
}

---@return AvanteLLMTool use_mcp_tool
---@return AvanteLLMTool access_mcp_resource
function M.mcp_tool()
    ---@param str string
    ---@param max_length number
    ---@return string
    local function truncate_utf8(str, max_length)
        if type(str) ~= "string" or #str <= max_length then
            return str
        end
        local i = 1
        local bytes = #str
        while i <= bytes and i < max_length do
            local c = string.byte(str, i)
            if c < 0x80 then
                i = i + 1
            elseif c < 0xE0 then
                i = i + 2
            elseif c < 0xF0 then
                i = i + 3
            else
                i = i + 4
            end
        end
        return str:sub(1, i - 1) .. "... (truncated)"
    end

    local async = require("plenary.async")
    local shared = require("mcphub.extensions.shared")
    for action_name, schema in pairs(tool_schemas) do
        ---@type AvanteLLMToolFunc<MCPHub.ToolCallArgs | MCPHub.ResourceAccessArgs>
        schema.func = function(args, opts)
            opts = opts or {}
            local on_complete = opts.on_complete or function() end
            local on_log = opts.on_log or function() end
            ---@diagnostic disable-next-line: missing-parameter
            async.run(function()
                local hub = require("mcphub").get_hub_instance()
                if not hub then
                    return on_complete(nil, "MCP Hub not initialized")
                end
                local params = shared.parse_params(args, action_name)
                if #params.errors > 0 then
                    return on_complete(nil, table.concat(params.errors, "\n"))
                end

                local result = shared.handle_auto_approval_decision(params)
                if result.error then
                    return on_complete(nil, result.error)
                end
                local sidebar = require("avante").get()
                if params.action == "access_mcp_resource" then
                    if on_log and type(on_log) == "function" then
                        on_log(
                            string.format("Accessing `%s` resource from server `%s`", params.uri, params.server_name)
                        )
                    end
                    hub:access_resource(params.server_name, params.uri, {
                        parse_response = true,
                        caller = {
                            type = "avante",
                            avante = sidebar,
                            auto_approve = result.approve,
                        },
                        callback = function(result, err)
                            --result has .text and .images [{mimeType, data}]
                            on_complete(result.text, err)
                        end,
                    })
                elseif params.action == "use_mcp_tool" then
                    if on_log and type(on_log) == "function" then
                        on_log(
                            string.format(
                                "Calling tool `%s` on server `%s` with arguments: %s",
                                params.tool_name,
                                params.server_name,
                                vim.inspect(params.arguments, {
                                    indent = "  ",
                                    depth = 2,
                                    process = function(item)
                                        return truncate_utf8(item, 80)
                                    end,
                                })
                            )
                        )
                    end
                    hub:call_tool(params.server_name, params.tool_name, params.arguments, {
                        parse_response = true,
                        caller = {
                            type = "avante",
                            avante = sidebar,
                            auto_approve = result.approve,
                        },
                        callback = function(result, err)
                            if result.error then
                                on_complete(nil, result.error)
                            else
                                on_complete(result.text, err)
                            end
                        end,
                    })
                else
                    return on_complete(nil, "Invalid action type")
                end
            end)
        end

        ---@type AvanteLLMToolReturn[]
        schema.returns = {
            {
                name = "result",
                description = string.format("The `%s` call returned the following text:\n", action_name),
                type = "string",
            },
            {
                name = "error",
                description = string.format("The `%s` call failed with the following error:\n", action_name),
                type = "string",
                optional = true,
            },
        }
        M[action_name] = schema
    end
    ---@diagnostic disable-next-line: redundant-return-value
    return unpack(vim.tbl_values(tool_schemas))
end

---@param config MCPHub.Extensions.AvanteConfig
function M.setup(config)
    if config.make_slash_commands then
        --Avoid checking for avante if the extension is not enabled
        local ok, _ = pcall(require, "avante")
        if not ok then
            return
        end
        require("mcphub.extensions.avante.slash_commands").setup()
    end
end

return M
