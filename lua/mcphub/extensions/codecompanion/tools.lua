local M = {}
local core = require("mcphub.extensions.codecompanion.core")

local mcphub = require("mcphub")

--- Utility functions for naming
---@param name string
---@return string
local function make_safe_name(name)
    name = name:gsub("[^%w_]", "_")
    return name
end

---@param server_name string Name of the MCP server
---@param tool_name string Tool name
---@return string
local function create_namespaced_tool_name(server_name, tool_name)
    local safe_server_name = make_safe_name(server_name)
    local safe_tool_name = make_safe_name(tool_name)
    return safe_server_name .. "__" .. safe_tool_name
end

--- Create handler for static tools (use_mcp_tool, access_mcp_resource)
---@param action_name MCPHub.ActionType
---@param has_function_calling boolean
---@param opts MCPHub.Extensions.CodeCompanionConfig
local function create_static_handler(action_name, has_function_calling, opts)
    ---@param agent CodeCompanion.Agent The Editor tool
    ---@param args MCPHub.ToolCallArgs | MCPHub.ResourceAccessArgs The arguments from the LLM's tool call
    ---@param output_handler function Callback for asynchronous calls
    ---@return nil|{ status: "success"|"error", data: string }
    return function(agent, args, _, output_handler)
        local context = {
            tool_display_name = action_name,
            is_individual_tool = false,
            action = action_name,
        }
        core.execute_mcp_tool(args, agent, output_handler, context)
    end
end

---@class MCPHub.ToolCallContext
---@field tool_display_name string
---@field is_individual_tool boolean
---@field action MCPHub.ActionType

--- Create handler for individual tools
---@param server_name string MCP Server name
---@param tool_name string Tool name on the server
---@param namespaced_name string Namespaced tool name (safe_server_name__safe_tool_name)
---@return function
local function create_individual_tool_handler(server_name, tool_name, namespaced_name)
    ---@param agent CodeCompanion.Agent The Editor tool
    ---@param args MCPHub.ToolCallArgs
    ---@param output_handler function Callback for asynchronous calls
    return function(agent, args, _, output_handler)
        local params = {
            server_name = server_name,
            tool_name = tool_name,
            tool_input = args,
        }
        ---@type MCPHub.ToolCallContext
        local context = {
            tool_display_name = namespaced_name,
            is_individual_tool = true,
            action = "use_mcp_tool",
        }
        core.execute_mcp_tool(params, agent, output_handler, context)
    end
end

-- Static tool schemas
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
                required = { "server_name", "uri" },
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
                required = { "server_name", "tool_name", "tool_input" },
                additionalProperties = false,
            },
            strict = false,
        },
    },
}

--- Create static MCP tools
---@param opts MCPHub.Extensions.CodeCompanionConfig
---@return {groups: table<string, table>, [MCPHub.ActionType]: table}
function M.create_static_tools(opts)
    local codecompanion = require("codecompanion")
    local has_function_calling = codecompanion.has("function-calling") --[[@as boolean]]

    local tools = {
        groups = {
            mcp = {
                id = "mcp_static:mcp",
                description = " Call tools and resources from MCP servers with:\n\n - `use_mcp_tool`\n - `access_mcp_resource`\n",
                hide_in_help_window = false,
                system_prompt = function(_)
                    local hub = require("mcphub").get_hub_instance()
                    if not hub then
                        vim.notify("MCP Hub is not initialized", vim.log.levels.WARN)
                        return ""
                    end
                    if not hub:is_ready() then
                        vim.notify("MCP Hub is not ready yet", vim.log.levels.WARN)
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
                opts = {
                    collapse_tools = true,
                },
            },
        },
    }

    for action_name, schema in pairs(tool_schemas) do
        tools[action_name] = {
            id = "mcp_static:" .. action_name,
            description = schema["function"].description,
            hide_in_help_window = true,
            visible = false,
            ---@class MCPHub.Extensions.CodeCompanionTool: CodeCompanion.Agent.Tool
            callback = {
                name = action_name,
                cmds = { create_static_handler(action_name, has_function_calling, opts) },
                system_prompt = function()
                    return string.format("You can use the %s tool to %s\n", action_name, schema["function"].description)
                end,
                output = core.create_output_handlers(action_name, has_function_calling, opts),
                schema = schema,
            },
        }
        table.insert(tools.groups.mcp.tools, action_name)
    end

    return tools
end

-- Cleanup dynamic tools and groups
local function cleanup_dynamic_items(config)
    local tools = config.interactions.chat.tools
    local groups = tools.groups or {}

    -- Clean up existing MCP dynamic tools
    for key, value in pairs(tools) do
        local id = value.id or ""
        if id:sub(1, 11) == "mcp_dynamic" then
            tools[key] = nil
        end
    end

    -- Clean up existing MCP dynamic tool groups
    for key, value in pairs(groups) do
        local id = value.id or ""
        if id:sub(1, 11) == "mcp_dynamic" then
            groups[key] = nil
        end
    end
end

---@param opts MCPHub.Extensions.CodeCompanionConfig
function M.register(opts)
    local hub = mcphub.get_hub_instance()
    if not hub then
        return
    end

    local ok, config = pcall(require, "codecompanion.config")
    if not ok then
        return
    end

    -- Cleanup existing dynamic items
    cleanup_dynamic_items(config)

    local tools = config.interactions.chat.tools
    local groups = tools.groups or {}

    -- Get servers and process in one go
    local servers = hub:get_servers()
    local server_tools = {} -- Map safe_server_name -> {tool_names, server_name}
    local used_safe_names = {}
    local skipped_tools = {}
    local skipped_groups = {}

    -- Process servers: create unique safe names and individual tools
    for _, server in ipairs(servers) do
        local safe_name = make_safe_name(server.name)
        local counter = 1
        local original_safe_name = safe_name

        -- Ensure unique safe name
        while used_safe_names[safe_name] do
            safe_name = original_safe_name .. "_" .. counter
            counter = counter + 1
        end

        used_safe_names[safe_name] = true

        if opts.add_mcp_prefix_to_tool_names then
            safe_name = "mcp__" .. safe_name
        end
        -- Check if this safe_name conflicts with existing group
        if groups[safe_name] then
            table.insert(skipped_groups, safe_name)
            -- Skip this entire server to avoid confusing individual tools
            goto continue
        end

        server_tools[safe_name] = { tool_names = {}, server_name = server.name }

        -- Create individual tools for this server
        if server.capabilities and server.capabilities.tools then
            for _, tool in ipairs(server.capabilities.tools) do
                local tool_name = tool.name
                local namespaced_tool_name = create_namespaced_tool_name(safe_name, tool_name)
                -- Check for tool name conflicts (after cleanup, no mcp_dynamic should exist)
                if tools[namespaced_tool_name] then
                    table.insert(skipped_tools, namespaced_tool_name)
                else
                    -- Track for server group
                    table.insert(server_tools[safe_name].tool_names, namespaced_tool_name)

                    -- Add individual tool
                    tools[namespaced_tool_name] = {
                        id = "mcp_dynamic:" .. safe_name .. ":" .. tool_name,
                        description = tool.description,
                        hide_in_help_window = true,
                        visible = opts.show_server_tools_in_chat == true,
                        callback = {
                            name = namespaced_tool_name,
                            cmds = { create_individual_tool_handler(server.name, tool_name, namespaced_tool_name) },
                            output = core.create_output_handlers(namespaced_tool_name, true, opts),
                            schema = {
                                type = "function",
                                ["function"] = {
                                    name = namespaced_tool_name,
                                    description = tool.description,
                                    parameters = tool.inputSchema,
                                },
                            },
                        },
                    }
                end
            end
        end

        ::continue::
    end

    -- Create server groups
    local prompt_utils = require("mcphub.utils.prompt")
    for safe_server_name, server_data in pairs(server_tools) do
        local tool_names = server_data.tool_names
        local server_name = server_data.server_name

        -- Only create group if it has tools and no conflict
        if #tool_names > 0 then
            if groups[safe_server_name] then
                table.insert(skipped_groups, safe_server_name)
            else
                local custom_instructions = prompt_utils.format_custom_instructions(
                    server_name,
                    "\n\n### Instructions for " .. safe_server_name .. " tools\n\n"
                )

                groups[safe_server_name] = {
                    id = "mcp_dynamic:" .. safe_server_name,
                    hide_in_help_window = true,
                    description = string.format(
                        " All tools from `%s` MCP server: \n\n%s",
                        server_name,
                        table.concat(
                            vim.tbl_map(function(t)
                                return " - `" .. t .. "` "
                            end, tool_names),
                            "\n"
                        )
                    ),
                    tools = tool_names,
                    system_prompt = function(self)
                        if custom_instructions and custom_instructions ~= "" then
                            return custom_instructions
                        end
                    end,
                    opts = {
                        collapse_tools = true,
                    },
                }
            end
        end
    end

    -- Silent warnings for conflicts
    if #skipped_tools > 0 then
        vim.notify(
            string.format(
                "Skipped adding %d tool(s) to codecompanion due to name conflicts: %s",
                #skipped_tools,
                table.concat(skipped_tools, ", ")
            ),
            vim.log.levels.WARN,
            { title = "MCPHub" }
        )
    end

    if #skipped_groups > 0 then
        vim.notify(
            string.format(
                "Skipped adding %d server group(s) to codecompanion due to name conflicts: %s",
                #skipped_groups,
                table.concat(skipped_groups, ", ")
            ),
            vim.log.levels.WARN,
            { title = "MCPHub" }
        )
    end

    -- Update syntax highlighting
    M.update_syntax_highlighting(server_tools)
end

--- Setup dynamic tools (individual tools + server groups)
---@param opts MCPHub.Extensions.CodeCompanionConfig
function M.setup_dynamic_tools(opts)
    if not opts.make_tools then
        return
    end
    vim.schedule(function()
        M.register(opts)
    end)
    mcphub.on(
        { "servers_updated", "tool_list_changed" },
        vim.schedule_wrap(function()
            M.register(opts)
        end)
    )
end

-- Update syntax highlighting for new tools
function M.update_syntax_highlighting(server_tools)
    vim.schedule(function()
        for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
            if vim.api.nvim_buf_is_valid(bufnr) and vim.bo[bufnr].filetype == "codecompanion" then
                vim.api.nvim_buf_call(bufnr, function()
                    for safe_server_name, server_data in pairs(server_tools) do
                        local tool_names = server_data.tool_names
                        vim.cmd.syntax('match CodeCompanionChatToolGroup "@{' .. safe_server_name .. '}"')
                        vim.iter(tool_names):each(function(name)
                            vim.cmd.syntax('match CodeCompanionChatTool "@{' .. name .. '}"')
                        end)
                    end
                end)
            end
        end
    end)
end

return M
