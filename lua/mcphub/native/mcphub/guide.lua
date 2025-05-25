local mcphub = require("mcphub")
local prompt_utils = require("mcphub.utils.prompt")

mcphub.add_tool("mcphub", {
    name = "get_current_servers",
    description = "Get the current state of all MCP servers (connected and disabled). This is useful when you need to know what servers are currently available, especially when restoring chat from history or when server state may have changed.",
    inputSchema = {
        type = "object",
        properties = {
            include_disabled = {
                type = "boolean",
                description = "Whether to include disabled servers in the response (default: true)",
                default = true,
            },
            format = {
                type = "string",
                description = "Response format: 'detailed' for full server info or 'summary' for compact list (default: detailed)",
                enum = { "detailed", "summary" },
                default = "detailed",
            },
        },
    },
    handler = function(req, res)
        local hub = mcphub.get_hub_instance()
        if not hub or not hub:is_ready() then
            return res:error("Hub is not ready")
        end

        local include_disabled = req.params.include_disabled ~= false -- default to true
        local format = req.params.format or "detailed"

        if format == "summary" then
            local connected_count = 0
            local disabled_count = 0
            local server_names = { connected = {}, disabled = {} }

            local servers = hub:get_servers(include_disabled)
            for _, server in ipairs(servers) do
                if server.status == "connected" then
                    connected_count = connected_count + 1
                    table.insert(server_names.connected, server.name)
                elseif server.status == "disabled" then
                    disabled_count = disabled_count + 1
                    table.insert(server_names.disabled, server.name)
                end
            end

            local summary = string.format(
                "# Current MCP Server Status\n\n" .. "Connected servers (%d): %s\n" .. "Disabled servers (%d): %s",
                connected_count,
                #server_names.connected > 0 and table.concat(server_names.connected, ", ") or "None",
                disabled_count,
                #server_names.disabled > 0 and table.concat(server_names.disabled, ", ") or "None"
            )

            return res:text(summary):send()
        else
            -- Detailed format using the existing active servers prompt
            local detailed_info = hub:get_active_servers_prompt(true, include_disabled)
            return res:text(detailed_info):send()
        end
    end,
})

mcphub.add_tool("mcphub", {
    name = "toggle_mcp_server",
    description = "Start or stop an MCP server. You can only start a server from one of the disabled servers.",
    inputSchema = {
        type = "object",
        properties = {
            server_name = {
                type = "string",
                description = "Name of the MCP server to toggle",
            },
            action = {
                type = "string",
                description = "Action to perform. One of 'start' or 'stop'",
                enum = { "start", "stop" },
            },
        },
        required = { "server_name", "action" },
    },
    handler = function(req, res)
        local hub = mcphub.get_hub_instance()
        if not hub or not hub:is_ready() then
            return res:error("Hub is not ready")
        end

        local server_name = req.params.server_name
        local action = req.params.action
        if not server_name or not action then
            return res:error("Missing required parameters: server_name and action")
        end

        -- Check if server exists in current state
        local found = false
        for _, server in ipairs(hub:get_servers(true)) do
            if server.name == server_name then
                found = true
                break
            end
        end

        if not found then
            return res:error(string.format("Server '%s' not found in active servers", server_name))
        end

        --INFO: via_curl_request: because we can wait for the server to start or stop and send the correct status to llm rather than sse event based on file wathing which is more appropriate for UI
        if action == "start" then
            hub:start_mcp_server(server_name, {
                via_curl_request = true,
                callback = function(response, err)
                    if err then
                        return res:error(string.format("Failed to start MCP server: %s", err))
                    end
                    local server = response and response.server
                    return res
                        :text(
                            string.format("Started MCP server: %s\n%s", server_name, hub:convert_server_to_text(server))
                        )
                        :send()
                end,
            })
        elseif action == "stop" then
            hub:stop_mcp_server(server_name, true, {
                via_curl_request = true,
                callback = function(_, err)
                    if err then
                        return res:error(string.format("Failed to stop MCP server: %s", err))
                    end
                    return res:text(string.format("Stopped MCP server: %s.", server_name)):send()
                end,
            })
        else
            return res:error(string.format("Invalid action '%s'. Use 'start' or 'stop'", action))
        end
    end,
})

mcphub.add_resource("mcphub", {
    name = "MCPHub Plugin Docs",
    mimeType = "text/plain",
    uri = "mcphub://docs",
    description = [[Documentation for the mcphub.nvim plugin for Neovim.]],
    handler = function(_, res)
        local guide = prompt_utils.get_plugin_docs()
        if not guide then
            return res:error("Plugin docs not available")
        end
        return res:text(guide):send()
    end,
})

mcphub.add_resource("mcphub", {
    name = "MCPHub Native Server Guide",
    mimeType = "text/plain",
    uri = "mcphub://native_server_guide",
    description = [[Documentation on how to create Lua Native MCP servers for mcphub.nvim plugin.
This guide is intended for Large language models to help users create their own native servers for mcphub.nvim plugin.
Access this guide whenever you need information on how to create a native server for mcphub.nvim plugin.]],
    handler = function(_, res)
        local guide = prompt_utils.get_native_server_prompt()
        if not guide then
            return res:error("Native server guide not available")
        end
        return res:text(guide):send()
    end,
})

mcphub.add_resource("mcphub", {
    name = "MCPHub Changelog",
    mimeType = "text/plain",
    uri = "mcphub://changelog",
    description = [[Changelog for the mcphub.nvim plugin for Neovim.]],
    handler = function(_, res)
        local guide = prompt_utils.get_plugin_changelog()
        if not guide then
            return res:error("Plugin changelog not available")
        end
        return res:text(guide):send()
    end,
})
