local NuiLine = require("mcphub.utils.nuiline")
local State = require("mcphub.state")
local Text = require("mcphub.utils.text")
local utils = require("mcphub.utils")

local M = {}

--- Get server status information
---@param status string Server status
---@return { icon: string, desc: string, hl: string } Status info
function M.get_server_status_info(status, expanded)
    return {
        icon = ({
            connected = (expanded and Text.icons.triangleDown or Text.icons.triangleRight) .. " ",
            connecting = "◉ ",
            disconnecting = "○ ",
            disconnected = "○ ",
            disabled = "○ ",
        })[status] or "⚠ ",

        desc = ({
            connecting = " (connecting...)",
            disconnecting = " (disconnecting...)",
        })[status] or "",

        hl = ({
            connected = Text.highlights.success,
            connecting = Text.highlights.success,
            disconnecting = Text.highlights.warning,
            disconnected = Text.highlights.warning,
            disabled = Text.highlights.muted,
        })[status] or Text.highlights.error,
    }
end

--- Render a server line
---@param server table Server data
---@return { line: NuiLine, mapping: table? }
function M.render_server_line(server, active)
    local status = M.get_server_status_info(server.status, active)
    local line = NuiLine():append(status.icon, status.hl):append(
        server.displayName or server.name,
        server.status == "connected" and Text.highlights.success or status.hl
    )

    -- Add error message for disconnected servers
    if server.error ~= vim.NIL and server.status == "disconnected" and server.error ~= "" then
        -- Get first line of error message
        local error_lines = Text.multiline(server.error, Text.highlights.error)
        line:append(" - ", Text.highlights.muted):append(error_lines[1], Text.highlights.error)
    end

    -- Add capabilities counts inline for connected servers
    if server.status == "connected" and server.capabilities then
        if #server.capabilities.tools > 0 then
            local server_config = State.servers_config[server.name] or {}
            local disabled_tools = server_config.disabled_tools or {}
            local enabled_tools = #server.capabilities.tools - #disabled_tools

            line:append(" ", Text.highlights.muted):append(Text.icons.tool, Text.highlights.info):append(
                " "
                    .. tostring(enabled_tools)
                    .. (#disabled_tools > 0 and "/" .. tostring(#server.capabilities.tools) or ""),
                Text.highlights.info
            )
        end
        if #server.capabilities.resources > 0 then
            line:append(" ", Text.highlights.muted)
                :append(Text.icons.resource, Text.highlights.warning)
                :append(" " .. tostring(#server.capabilities.resources), Text.highlights.warning)
        end
        if #server.capabilities.resourceTemplates > 0 then
            line:append(" ", Text.highlights.muted)
                :append(Text.icons.resourceTemplate, Text.highlights.error)
                :append(" " .. tostring(#server.capabilities.resourceTemplates), Text.highlights.error)
        end
    end

    -- Add status description if any
    if status.desc ~= "" then
        line:append(status.desc, Text.highlights.muted)
    end

    return line
end

--- Render server details with capabilities
---@param server table Server data
---@param line_offset number Current line offset
---@param options? { expanded: boolean } Render options
---@return { lines: NuiLine[], mappings: table[] }
function M.render_server_details(server, line_offset, options)
    options = options or {
        expanded = true,
    }
    local lines = {}
    local mappings = {}
    local current_line = line_offset

    -- Render server line
    local server_render = M.render_server_line(server)
    table.insert(lines, Text.pad_line(server_render.line, nil, 4))
    current_line = current_line + 1

    -- Track server line
    if server_render.mapping then
        server_render.mapping.line = current_line
        table.insert(mappings, server_render.mapping)
    end

    -- Show capabilities based on view mode
    if server.capabilities then
        if options.expanded then
            -- Server details
            if server.uptime then
                local uptime = NuiLine():append("│ ", Text.highlights.muted):append(
                    string.format("Uptime: %s", utils.format_uptime(server.uptime)),
                    Text.highlights.muted
                )
                table.insert(lines, Text.pad_line(uptime))
                current_line = current_line + 1
            end

            -- Show capabilities only for connected servers
            if server.status == "connected" and server.capabilities then
                -- Show tools section
                table.insert(lines, Text.pad_line(NuiLine():append("│", Text.highlights.muted)))
                current_line = current_line + 1

                table.insert(
                    lines,
                    Text.pad_line(
                        NuiLine():append("│ ", Text.highlights.muted):append("Tools:", Text.highlights.muted)
                    )
                )
                current_line = current_line + 1

                -- Show tools if any
                if #server.capabilities.tools > 0 then
                    for _, tool in ipairs(server.capabilities.tools) do
                        local tool_line = NuiLine()
                            :append("│  • ", Text.highlights.muted)
                            :append(tool.name, Text.highlights.success)
                        table.insert(lines, Text.pad_line(tool_line))
                        current_line = current_line + 1

                        -- Track tool line
                        table.insert(mappings, {
                            line = current_line,
                            type = "tool",
                            context = vim.tbl_extend("force", tool, {
                                server_name = server.name,
                                hint = "Press <CR> to use tool",
                            }),
                        })
                    end
                end

                -- Show resources section
                table.insert(lines, Text.pad_line(NuiLine():append("│", Text.highlights.muted)))
                current_line = current_line + 1

                table.insert(
                    lines,
                    Text.pad_line(
                        NuiLine():append("│ ", Text.highlights.muted):append("Resources:", Text.highlights.muted)
                    )
                )
                current_line = current_line + 1

                -- Show resources if any
                if #server.capabilities.resources > 0 then
                    for _, resource in ipairs(server.capabilities.resources) do
                        local resource_line = NuiLine()
                            :append("│  • ", Text.highlights.muted)
                            :append(resource.name, Text.highlights.success)
                            :append(" (", Text.highlights.muted)
                            :append(resource.mimeType or "unknown", Text.highlights.info)
                            :append(")", Text.highlights.muted)
                        table.insert(lines, Text.pad_line(resource_line))
                        current_line = current_line + 1

                        -- Track resource line
                        table.insert(mappings, {
                            line = current_line,
                            type = "resource",
                            context = vim.tbl_extend("force", resource, {
                                server_name = server.name,
                                hint = "Press <CR> to access resource",
                            }),
                        })
                    end
                end
            end
        else
            -- Compact view with capabilities summary
            if server.capabilities and server.status == "connected" then
                local cap_parts = {}
                if #server.capabilities.tools > 0 then
                    table.insert(cap_parts, string.format("Tools: %d", #server.capabilities.tools))
                end
                if #server.capabilities.resources > 0 then
                    table.insert(cap_parts, string.format("Resources: %d", #server.capabilities.resources))
                end
                if #cap_parts > 0 then
                    local cap_line = NuiLine()
                        :append("  └─ ", Text.highlights.muted)
                        :append(table.concat(cap_parts, ", "), Text.highlights.info)
                    table.insert(lines, Text.pad_line(cap_line, nil, 4))
                    current_line = current_line + 1
                end
            end
        end
    end

    table.insert(lines, Text.empty_line())
    return {
        lines = lines,
        mappings = mappings,
    }
end

--- Sort and render a list of servers
---@param servers table[] List of servers
---@param line_offset number Current line offset
---@param options? { expanded: boolean } Render options
---@return { lines: NuiLine[], mappings: table[] }
function M.render_servers(servers, line_offset, options)
    -- Sort servers: connected first, disabled last
    table.sort(servers, function(a, b)
        if a.status == "disabled" then
            return false
        end
        if b.status == "disabled" then
            return true
        end
        return a.name < b.name
    end)

    local lines = {}
    local mappings = {}
    local current_line = line_offset

    for _, server in ipairs(servers) do
        local result = M.render_server_details(server, current_line, options)
        vim.list_extend(lines, result.lines)
        vim.list_extend(mappings, result.mappings)
        current_line = current_line + #result.lines
    end

    return {
        lines = lines,
        mappings = mappings,
    }
end

-- Format timestamp (could be Unix timestamp or ISO string)
local function format_time(timestamp)
    -- For Unix timestamps
    return os.date("%H:%M:%S", math.floor(timestamp / 1000))
end

--- Render error lines without header
---@param type? string Optional error type to filter (setup/server/runtime)
---@param detailed? boolean Whether to show full error details
---@return NuiLine[] Lines
function M.render_hub_errors(error_type, detailed)
    local lines = {}
    local errors = State:get_errors(error_type)

    if #errors > 0 then
        for _, err in ipairs(errors) do
            -- Get appropriate icon based on error type
            local error_icon = ({
                SETUP = Text.icons.setup_error,
                SERVER = Text.icons.server_error,
                RUNTIME = Text.icons.runtime_error,
            })[err.type] or Text.icons.error

            -- Handle multiline error messages
            local message_lines = Text.multiline(err.message, Text.highlights.error)

            -- First line with icon and timestamp
            local first_line = NuiLine()
            first_line:append(error_icon .. " ", Text.highlights.error)
            first_line:append(message_lines[1], Text.highlights.error)
            if err.timestamp then
                first_line:append(" (" .. utils.format_relative_time(err.timestamp) .. ")", Text.highlights.muted)
            end
            table.insert(lines, Text.pad_line(first_line))

            -- Add remaining lines with proper indentation
            for i = 2, #message_lines do
                local line = NuiLine()
                line:append(message_lines[i], Text.highlights.error)
                table.insert(lines, Text.pad_line(line, nil, 4))
            end

            -- Add error details if detailed mode and details exist
            if detailed and err.details and next(err.details) then
                -- Convert details to string
                local detail_text = type(err.details) == "string" and err.details or vim.inspect(err.details)

                -- Add indented details
                local detail_lines = vim.tbl_map(function(l)
                    return Text.pad_line(l, nil, 4)
                end, Text.multiline(detail_text, Text.highlights.muted))
                vim.list_extend(lines, detail_lines)
                table.insert(lines, Text.empty_line())
            end
        end
    end

    return lines
end

--- Render server entry logs without header
---@param entries table[] Array of log entries
---@return NuiLine[] Lines
function M.render_server_entries(entries)
    local lines = {}

    if #entries > 0 then
        for _, entry in ipairs(entries) do
            if entry.timestamp and entry.message then
                local line = NuiLine()
                -- Add timestamp
                line:append(string.format("[%s] ", format_time(entry.timestamp)), Text.highlights.muted)

                -- Add type icon and message
                line:append(
                    (Text.icons[entry.type] or "•") .. " ",
                    Text.highlights[entry.type] or Text.highlights.muted
                )

                -- Add error code if present
                if entry.code then
                    line:append(string.format("[Code: %s] ", entry.code), Text.highlights.muted)
                end

                -- Add main message
                line:append(entry.message, Text.highlights[entry.type] or Text.highlights.muted)

                table.insert(lines, Text.pad_line(line))
            end
        end
    end

    return lines
end

return M
