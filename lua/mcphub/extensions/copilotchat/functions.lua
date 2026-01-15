local M = {}
local mcphub = require("mcphub")

---@param name string
---@return string
local function make_safe_name(name)
    return (name:gsub("[^%w_]", "_"))
end

---@param uri string|nil
---@return string
local function extract_name_from_uri(uri)
    if not uri then
        return "unknown"
    end

    -- Replace all non-alphanumeric characters with underscores
    local name = uri:gsub("[^%w]", "_")

    -- Remove leading/trailing underscores and collapse multiple underscores
    name = name:gsub("^_+", ""):gsub("_+$", ""):gsub("_+", "_")

    return name ~= "" and name or "unknown"
end

---@param server_name string
---@param item_name string
---@param opts MCPHub.Extensions.CopilotChatConfig
---@return string
local function create_function_name(server_name, item_name, opts)
    local safe_server = make_safe_name(server_name)
    local safe_item = make_safe_name(item_name)
    local name = safe_server .. "_" .. safe_item

    if opts and opts.add_mcp_prefix then
        name = "mcp_" .. name
    end

    -- Limit the name to 64 characters
    if #name > 64 then
        name = name:sub(1, 64)
    end

    return name
end

-- Cleanup existing mcphub functions
local function cleanup_mcphub_functions(chat)
    if not chat.config.functions then
        return
    end

    for name, func in pairs(chat.config.functions) do
        if func._mcphub then
            chat.config.functions[name] = nil
        end
    end
end

--- Register MCP tools and resources as CopilotChat functions
---@param opts MCPHub.Extensions.CopilotChatConfig
function M.register(opts)
    local hub = mcphub.get_hub_instance()
    if not hub then
        return
    end

    local ok, chat = pcall(require, "CopilotChat")
    if not ok then
        return
    end

    if not chat.config.functions then
        return
    end

    local async = require("plenary.async")
    local chat_functions = require("CopilotChat.functions")
    local shared = require("mcphub.extensions.shared")

    -- Cleanup existing mcphub functions
    cleanup_mcphub_functions(chat)

    -- Create async wrappers with proper event loop scheduling
    local call_tool = async.wrap(function(server, tool, input, callback)
        -- Schedule the MCP call to run in the main event loop to avoid fast event context issues
        vim.schedule(function()
            hub:call_tool(server, tool, input, {
                caller = {
                    type = "copilotchat",
                    copilotchat = chat,
                },
                callback = function(res, err)
                    callback(res, err)
                end,
            })
        end)
    end, 4)

    local access_resource = async.wrap(function(server, uri, callback)
        vim.schedule(function()
            hub:access_resource(server, uri, {
                caller = {
                    type = "copilotchat",
                    copilotchat = chat,
                },
                callback = function(res, err)
                    callback(res, err)
                end,
            })
        end)
    end, 3)

    -- Get servers and process them to avoid name conflicts
    local servers = hub:get_servers()
    local server_data = {} -- Map safe_server_name -> {server_name, tools, resources}
    local used_safe_names = {}
    local skipped_functions = {}

    -- Process servers: create unique safe names
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

        server_data[safe_name] = {
            server_name = server.name,
            tools = server.capabilities and server.capabilities.tools or {},
            resources = server.capabilities and server.capabilities.resources or {},
            resource_templates = server.capabilities and server.capabilities.resourceTemplates or {},
        }
    end

    -- Register MCP tools as functions
    if opts.convert_tools_to_functions then
        for safe_server_name, data in pairs(server_data) do
            local server_name = data.server_name
            local tools = data.tools

            for _, tool in ipairs(tools) do
                local function_name = create_function_name(safe_server_name, tool.name, opts)

                -- Check for function name conflicts
                if chat.config.functions[function_name] then
                    table.insert(skipped_functions, function_name)
                else
                    chat.config.functions[function_name] = {
                        _mcphub = true,
                        group = safe_server_name,
                        description = tool.description or "No description provided",
                        schema = tool.inputSchema,
                        resolve = function(input)
                            -- Handle auto-approval
                            local params = shared.parse_params({
                                server_name = server_name,
                                tool_name = tool.name,
                                tool_input = input or {},
                            }, "use_mcp_tool")

                            if #params.errors > 0 then
                                error(table.concat(params.errors, "\n"))
                            end

                            -- TODO: Handle auto-approval logic if possible
                            -- local result = shared.handle_auto_approval_decision(params)
                            -- if result.error then
                            --     error(result.error)
                            -- end
                            --
                            -- if not result.approve and params.needs_confirmation_window then
                            --     local confirmed, _ = shared.show_mcp_tool_prompt(params)
                            --     if not confirmed then
                            --         error("User cancelled the operation")
                            --     end
                            -- end

                            local res, err = call_tool(server_name, tool.name, input or {})
                            if err then
                                error(err)
                            end

                            res = res or {}
                            local result_data = res.result or {}
                            local content = result_data.content or {}
                            local out = {}

                            for _, message in ipairs(content) do
                                if message.type == "text" then
                                    table.insert(out, {
                                        data = message.text,
                                    })
                                elseif message.type == "resource" and message.resource and message.resource.text then
                                    table.insert(out, {
                                        uri = message.resource.uri,
                                        data = message.resource.text,
                                        mimetype = message.resource.mimeType,
                                    })
                                end
                            end

                            return out
                        end,
                    }
                end
            end
        end
    end

    -- Register MCP resources as functions
    if opts.convert_resources_to_functions then
        for safe_server_name, data in pairs(server_data) do
            local server_name = data.server_name
            local resources = data.resources
            local resource_templates = data.resource_templates

            -- Handle regular resources
            for _, resource in ipairs(resources) do
                local resource_name = resource.name or extract_name_from_uri(resource.uri)
                local function_name = create_function_name(safe_server_name, resource_name, opts)

                -- Check for function name conflicts
                if chat.config.functions[function_name] then
                    table.insert(skipped_functions, function_name)
                else
                    chat.config.functions[function_name] = {
                        _mcphub = true,
                        uri = resource.uri,
                        group = safe_server_name,
                        description = resource.description or "No description provided",
                        resolve = function()
                            local res, err = access_resource(server_name, resource.uri)
                            if err then
                                error(err)
                            end

                            res = res or {}
                            local result_data = res.result or {}
                            local content = result_data.contents or {}
                            local out = {}

                            for _, message in ipairs(content) do
                                if message.text then
                                    table.insert(out, {
                                        uri = message.uri,
                                        data = message.text,
                                        mimetype = message.mimeType,
                                    })
                                end
                            end

                            return out
                        end,
                    }
                end
            end

            -- Handle resource templates
            for _, template in ipairs(resource_templates) do
                local template_name = template.name or extract_name_from_uri(template.uriTemplate)
                local function_name = create_function_name(safe_server_name, template_name, opts)

                -- Check for function name conflicts
                if chat.config.functions[function_name] then
                    table.insert(skipped_functions, function_name)
                else
                    chat.config.functions[function_name] = {
                        _mcphub = true,
                        uri = template.uriTemplate,
                        group = safe_server_name,
                        description = template.description or "No description provided",
                        resolve = function(input)
                            local url = chat_functions.uri_to_url(template.uriTemplate, input or {})
                            local res, err = access_resource(server_name, url)
                            if err then
                                error(err)
                            end

                            res = res or {}
                            local result_data = res.result or {}
                            local content = result_data.contents or {}
                            local out = {}

                            for _, message in ipairs(content) do
                                if message.text then
                                    table.insert(out, {
                                        uri = message.uri,
                                        data = message.text,
                                        mimetype = message.mimeType,
                                    })
                                end
                            end

                            return out
                        end,
                    }
                end
            end
        end
    end

    -- Report skipped functions due to conflicts
    if #skipped_functions > 0 then
        vim.notify(
            string.format(
                "Skipped adding %d function(s) to CopilotChat due to name conflicts: %s",
                #skipped_functions,
                table.concat(skipped_functions, ", ")
            ),
            vim.log.levels.WARN,
            { title = "MCPHub" }
        )
    end
end

--- Setup MCP tools and resources as CopilotChat functions
---@param opts MCPHub.Extensions.CopilotChatConfig
function M.setup(opts)
    -- Initial registration
    vim.schedule(function()
        M.register(opts)
    end)

    -- Listen for MCP server changes and re-register
    mcphub.on(
        { "servers_updated", "tool_list_changed", "resource_list_changed" },
        vim.schedule_wrap(function()
            M.register(opts)
        end)
    )
end

return M
