local NuiLine = require("mcphub.utils.nuiline")
local State = require("mcphub.state")
local Text = require("mcphub.utils.text")
local native = require("mcphub.native")
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

--- Render server capabilities section
---@param items table[] List of items
---@param title string Section title
---@param server_name string Server name
---@param type string Item type
---@param current_line number Current line number
---@return NuiLine[],number,table[] Lines, new current line, mappings
function M.render_cap_section(items, title, server_name, type, current_line)
    local lines = {}
    local mappings = {}

    local icons = {
        tool = Text.icons.tool,
        resource = Text.icons.resource,
        resourceTemplate = Text.icons.resourceTemplate,
    }
    table.insert(
        lines,
        Text.pad_line(NuiLine():append(" " .. icons[type] .. " " .. title .. ": ", Text.highlights.muted), nil, 4)
    )

    local is_native = native.is_native_server(server_name)
    local server_config = (is_native and State.native_servers_config[server_name] or State.servers_config[server_name])
        or {}
    local disabled_tools = server_config.disabled_tools or {}
    if type == "tool" then
        -- For tools, sort by name and move disabled ones to end
        local sorted_items = vim.deepcopy(items)
        table.sort(sorted_items, function(a, b)
            local a_disabled = vim.tbl_contains(disabled_tools, a.name)
            local b_disabled = vim.tbl_contains(disabled_tools, b.name)
            if a_disabled ~= b_disabled then
                return not a_disabled
            end
            return a.name < b.name
        end)
        items = sorted_items
    end

    for _, item in ipairs(items) do
        local is_disabled = type == "tool" and vim.tbl_contains(disabled_tools, item.name) or false

        local line = NuiLine()
        if is_disabled then
            line:append(Text.icons.circle .. " ", Text.highlights.muted):append(item.name, Text.highlights.muted)
        else
            line:append(Text.icons.arrowRight .. " ", Text.highlights.muted):append(item.name, Text.highlights.info)
        end

        if item.mimeType then
            line:append(" (" .. item.mimeType .. ")", Text.highlights.muted)
        end
        table.insert(lines, Text.pad_line(line, nil, 6))

        local hint
        if type == "tool" then
            hint = is_disabled and "Press 't' to enable tool" or "Press <CR> to use tool, 't' to disable"
        else
            hint = "Press <CR> to "
                .. ({
                    resource = "access resource",
                    resourceTemplate = "create from template",
                })[type]
        end

        table.insert(mappings, {
            line = current_line + #lines,
            type = type,
            context = vim.tbl_extend("force", item, {
                server_name = server_name,
                disabled = is_disabled,
                hint = hint,
            }),
        })
    end

    return lines, current_line + #lines, mappings
end

--- Function to render a single server's capabilities
---@param server table Server to render
---@param lines table[] Lines array to append to
---@param current_line number Current line number
---@param config_source table Config source for the server
---@param view MainView View instance for tracking
---@return number New current line
function M.render_server_capabilities(server, lines, current_line, config_source, view)
    local server_name_line = M.render_server_line(server, view.expanded_server == server.name)
    table.insert(lines, Text.pad_line(server_name_line, nil, 3))
    current_line = current_line + 1

    -- Prepare hover hint based on server status
    local hint
    if server.status == "disabled" then
        hint = "Press 't' to enable server"
    elseif server.status == "disconnected" then
        hint = "Press 't' to disable server"
    else
        hint = view.expanded_server == server.name and "Press <CR> to collapse"
            or "Press <CR> to expand, 't' to disable"
    end

    view:track_line(current_line, "server", {
        name = server.name,
        status = server.status,
        hint = hint,
    })

    -- Show expanded server capabilities
    if server.status == "connected" and server.capabilities and view.expanded_server == server.name then
        local server_config = config_source[server.name] or {}
        if
            #server.capabilities.tools + #server.capabilities.resources + #server.capabilities.resourceTemplates
            == 0
        then
            table.insert(
                lines,
                Text.pad_line(NuiLine():append("No capabilities available", Text.highlights.muted), nil, 6)
            )
            table.insert(lines, Text.empty_line())
            current_line = current_line + 2
        end

        local custom_instructions = server_config.custom_instructions or {}
        local is_disabled = custom_instructions.disabled == true
        local has_instructions = custom_instructions.text and #custom_instructions.text > 0
        local ci_line =
            NuiLine():append(is_disabled and Text.icons.circle or Text.icons.arrowRight, Text.highlights.muted):append(
                " Custom Instructions" .. (not is_disabled and not has_instructions and " (empty)" or ""),
                (is_disabled or not has_instructions) and Text.highlights.muted or Text.highlights.info
            )
        table.insert(lines, Text.pad_line(ci_line, nil, 5))
        current_line = current_line + 1
        view:track_line(current_line, "customInstructions", {
            server_name = server.name,
            disabled = is_disabled,
            name = Text.icons.instructions .. " Custom Instructions",
            hint = is_disabled and "Press 't' to enable instructions" or "Press <CR> to edit, 't' to disable",
        })
        table.insert(lines, Text.empty_line())
        current_line = current_line + 1

        -- Tools section if any
        if #server.capabilities.tools > 0 then
            local section_lines, new_line, mappings =
                M.render_cap_section(server.capabilities.tools, "Tools", server.name, "tool", current_line)
            vim.list_extend(lines, section_lines)
            for _, m in ipairs(mappings) do
                view:track_line(m.line, m.type, m.context)
            end
            table.insert(lines, Text.empty_line())
            current_line = new_line + 1
        end

        -- Resources section if any
        if #server.capabilities.resources > 0 then
            local section_lines, new_line, mappings =
                M.render_cap_section(server.capabilities.resources, "Resources", server.name, "resource", current_line)
            vim.list_extend(lines, section_lines)
            for _, m in ipairs(mappings) do
                view:track_line(m.line, m.type, m.context)
            end
            table.insert(lines, Text.empty_line())
            current_line = new_line + 1
        end

        -- Resource Templates section if any
        if #server.capabilities.resourceTemplates > 0 then
            local section_lines, new_line, mappings = M.render_cap_section(
                server.capabilities.resourceTemplates,
                "Resource Templates",
                server.name,
                "resourceTemplate",
                current_line
            )
            vim.list_extend(lines, section_lines)
            for _, m in ipairs(mappings) do
                view:track_line(m.line, m.type, m.context)
            end
            table.insert(lines, Text.empty_line())
            current_line = new_line + 1
        end
    end

    return current_line
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

    --INFO: when decoded from regualr mcp servers vim.NIL; for nativeservers we set nil, so check both
    -- Add error message for disconnected servers
    if (server.error ~= vim.NIL or server.error ~= nil) and server.status == "disconnected" and server.error ~= "" then
        vim.notify(vim.inspect(server), vim.log.levels.INFO)
        -- Get first line of error message
        local error_lines = Text.multiline(server.error, Text.highlights.error)
        line:append(" - ", Text.highlights.muted):append(error_lines[1], Text.highlights.error)
    end

    local is_native = native.is_native_server(server.name)
    local server_config = (is_native and State.native_servers_config[server.name] or State.servers_config[server.name])
        or {}
    -- Add capabilities counts inline for connected servers
    if server.status == "connected" and server.capabilities then
        if server_config.custom_instructions and server_config.custom_instructions.text ~= "" then
            local is_disabled = server_config.custom_instructions.disabled
            line:append(
                " " .. Text.icons.instructions .. " ",
                is_disabled and Text.highlights.muted or Text.highlights.success
            )
        end
        if #server.capabilities.tools > 0 then
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
            vim.list_extend(lines, M.render_error(err))
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

function M.render_error(err)
    local lines = {}
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
    return lines
end

return M
