--[[
*MCP Servers Tool adapted for function calling*
This tool can be used to call tools and resources from the MCP Servers.
--]]
local M = {}
local utils = require("mcphub.extensions.codecompanion.utils")

local tool_schemas = {
    access_mcp_resource = {
        type = "function",
        ["function"] = {
            name = "access_mcp_resource",
            description = "get resources on MCP servers.",
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
            description = "calls tools on MCP servers.",
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
            strict = false,
        },
    },
}

function M.create_tools(opts)
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
    for action_name, schema in pairs(tool_schemas) do
        tools[action_name] = {
            description = schema["function"].description,
            visible = false,
            callback = {
                name = action_name,
                cmds = { utils.create_handler(action_name, has_function_calling, opts) },
                system_prompt = function()
                    return string.format("You can use the %s tool to %s\n", action_name, schema["function"].description)
                end,
                output = utils.create_output_handlers(action_name, has_function_calling, opts),
                --for xml version we are not using schema anywhere so, no issue if we use function schema for xml also
                schema = schema,
            },
        }
        table.insert(tools.groups.mcp.tools, action_name)
    end
    return tools
end

local function silent_assert(condition, message)
    if not condition then
        vim.notify(message, vim.log.levels.WARN)
    end
end

function M.setup(opts)
    opts = vim.tbl_deep_extend("force", {
        make_vars = true,
        make_slash_commands = true,
        show_result_in_chat = true,
    }, opts or {})
    local ok, cc_config = pcall(require, "codecompanion.config")
    if not ok then
        return
    end
    -- Detect old mcp tool
    silent_assert(
        cc_config.strategies.chat.tools.mcp == nil,
        "MCP Hub: `mcp` tool in codecompanion.config.strategies.chat.tools is deprecated. Please remove it and see the CHANGELOG tab in the Help view (<H>) of MCPHub UI"
    )
    -- Make sure we are not overriding user's tools and groups
    silent_assert(
        cc_config.strategies.chat.tools.groups.mcp == nil,
        "MCP Hub: `@mcp` tool group already exists. Please remove it from your codecompanion.config.strategies.chat.tools.groups"
    )
    silent_assert(
        cc_config.strategies.chat.tools.access_mcp_resource == nil,
        "MCP Hub: `access_mcp_resource` tool already exists. Please remove it from your codecompanion.config.strategies.chat.tools"
    )
    silent_assert(
        cc_config.strategies.chat.tools.use_mcp_tool == nil,
        "MCP Hub: `use_mcp_tool` tool already exists. Please remove it from your codecompanion.config.strategies.chat.tools"
    )
    cc_config.strategies.chat.tools =
        vim.tbl_deep_extend("force", cc_config.strategies.chat.tools, M.create_tools(opts))
    utils.setup_codecompanion_variables(opts)
    utils.setup_codecompanion_slash_commands(opts)
end

return M
