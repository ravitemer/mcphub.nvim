local NuiLine = require("mcphub.utils.nuiline")
local State = require("mcphub.state")
local Text = require("mcphub.utils.text")
local constants = require("mcphub.utils.constants")
local native = require("mcphub.native")
local utils = require("mcphub.utils")

local M = {}

function M.get_hub_info(state)
    local icon = ({
        [constants.HubState.STARTING] = "◉ ",
        [constants.HubState.READY] = Text.icons.loaded .. " ",
        [constants.HubState.RESTARTING] = "◉ ",
        [constants.HubState.RESTARTED] = Text.icons.loaded .. " ",
        [constants.HubState.STOPPING] = "◉ ",
        [constants.HubState.STOPPED] = "○ ",
        [constants.HubState.ERROR] = Text.icons.error .. " ",
    })[state] or "⚠ "

    local desc = ({
        [constants.HubState.STARTING] = "Starting...",
        [constants.HubState.READY] = "Connected",
        [constants.HubState.RESTARTING] = "Restarting...",
        [constants.HubState.RESTARTED] = "Restarted",
        [constants.HubState.STOPPING] = "Stopping...",
        [constants.HubState.STOPPED] = "Stopped",
        [constants.HubState.ERROR] = "Error",
    })[state] or "Unknown"

    local hl = ({
        [constants.HubState.STARTING] = Text.highlights.success,
        [constants.HubState.READY] = Text.highlights.success,
        [constants.HubState.RESTARTING] = Text.highlights.success,
        [constants.HubState.RESTARTED] = Text.highlights.success,
        [constants.HubState.STOPPING] = Text.highlights.warning,
        [constants.HubState.STOPPED] = Text.highlights.warning,
        [constants.HubState.ERROR] = Text.highlights.error,
    })[state] or Text.highlights.error
    return {
        icon = icon,
        desc = desc,
        hl = hl,
    }
end

--- Get server status information
---@param status string Server status
---@return { icon: string, desc: string, hl: string } Status info
function M.get_server_status_info(status, expanded)
    return {
        icon = ({
            connected = (expanded and Text.icons.triangleDown or Text.icons.triangleRight) .. " ",
            connecting = "◉ ",
            restarting = "◉ ",
            unauthorized = Text.icons.unauthorized .. " ",
            disconnecting = "○ ",
            disconnected = "○ ",
            disabled = "○ ",
        })[status] or "⚠ ",

        desc = ({
            connecting = " (connecting...)",
            disconnecting = " (disconnecting...)",
            unauthorized = " (unauthorized)",
        })[status] or "",

        hl = ({
            connected = Text.highlights.success,
            connecting = Text.highlights.success,
            restarting = Text.highlights.success,
            disconnecting = Text.highlights.warning,
            disconnected = Text.highlights.warning,
            unauthorized = Text.highlights.warning,
            disabled = Text.highlights.muted,
        })[status] or Text.highlights.error,
    }
end

--- Render server capabilities section
---@param items table[] List of items
---@param title string Section title
---@param server_name string Server name
---@param line_type string Item type
---@param current_line number Current line number
---@return NuiLine[],number,table
function M.render_cap_section(items, title, server_name, line_type, current_line)
    local lines = {}
    local mappings = {}

    local icons = {
        tool = Text.icons.tool,
        resource = Text.icons.resource,
        resourceTemplate = Text.icons.resourceTemplate,
        prompt = Text.icons.prompt,
    }
    table.insert(
        lines,
        Text.pad_line(NuiLine():append(" " .. icons[line_type] .. " " .. title .. ": ", Text.highlights.muted), nil, 4)
    )

    local is_native = native.is_native_server(server_name)
    local server_config = (is_native and State.native_servers_config[server_name] or State.servers_config[server_name])
        or {}
    local disabled_tools = server_config.disabled_tools or {}
    if line_type == "tool" then
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
        local name = item.name or item.uri or item.uriTemplate or "NO NAME"
        local is_disabled = false
        if line_type == "tool" then
            is_disabled = vim.tbl_contains(disabled_tools, item.name)
        elseif line_type == "resource" then
            is_disabled = vim.tbl_contains(server_config.disabled_resources or {}, item.uri)
        elseif line_type == "resourceTemplate" then
            is_disabled = vim.tbl_contains(server_config.disabled_resourceTemplates or {}, item.uriTemplate)
        elseif line_type == "prompt" then
            is_disabled = vim.tbl_contains(server_config.disabled_prompts or {}, item.name)
        end

        local line = NuiLine()
        if is_disabled then
            line:append(Text.icons.circle .. " ", Text.highlights.muted):append(name, Text.highlights.muted)
        else
            line:append(Text.icons.arrowRight .. " ", Text.highlights.muted):append(name, Text.highlights.info)
        end

        if item.mimeType then
            line:append(" (" .. item.mimeType .. ")", Text.highlights.muted)
        end

        -- Show auto-approve status for tools
        if line_type == "tool" and not is_disabled then
            local auto_approve = server_config.autoApprove
            local tool_auto_approved = false

            if auto_approve == true then
                tool_auto_approved = true
            elseif type(auto_approve) == "table" and vim.islist(auto_approve) then
                tool_auto_approved = vim.tbl_contains(auto_approve, name)
            end

            if tool_auto_approved then
                line:append(" " .. Text.icons.auto, Text.highlights.success)
            end
        end

        table.insert(lines, Text.pad_line(line, nil, 6))

        local hint
        if is_disabled then
            hint = "[<t> Toggle]"
        elseif line_type == "tool" then
            hint = string.format("[<l> open %s, <t> Toggle, <a> Auto-approve]", line_type)
        else
            hint = string.format("[<l> open %s, <t> Toggle]", line_type)
        end
        table.insert(mappings, {
            line = current_line + #lines,
            type = line_type,
            context = {
                def = item,
                server_name = server_name,
                disabled = is_disabled,
                hint = hint,
            },
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
function M.render_server_capabilities(server, lines, current_line, config_source, view, is_native)
    local server_name_line = M.render_server_line(server, view.expanded_server == server.name)
    table.insert(lines, Text.pad_line(server_name_line, nil, 3))
    current_line = current_line + 1

    -- Prepare hover hint based on server status
    local base_hint_disabled = is_native and "[<t> Toggle, <e> Edit]" or "[<t> Toggle, <e> Edit, <d> Delete]"
    local base_hint_enabled = is_native and "[<t> Toggle, <a> Auto-approve, <e> Edit]"
        or "[<t> Toggle, <a> Auto-approve, <e> Edit, <d> Delete]"

    local needs_authorization = server.status == "unauthorized"
    local enabled_hint = is_native and "[<l> Expand, <t> Toggle, <a> Auto-approve, <e> Edit]"
        or needs_authorization and "[<l> Authorize, <t> Toggle, <a> Auto-approve, <e> Edit, <d> Delete]"
        or "[<l> Expand, <t> Toggle, <a> Auto-approve, <e> Edit, <d> Delete]"
    local expanded_hint = is_native and "[<h> Collapse, <t> Toggle, <a> Auto-approve, <e> Edit]"
        or "[<h> Collapse, <t> Toggle, <a> Auto-approve, <e> Edit, <d> Delete]"

    local hint
    if server.status == "disabled" or server.status == "disconnected" then
        hint = base_hint_disabled -- No auto-approve for disabled/disconnected servers
    else
        hint = view.expanded_server == server.name and expanded_hint or enabled_hint
    end

    view:track_line(current_line, "server", {
        name = server.name,
        status = server.status,
        hint = hint,
    })

    -- Show expanded server capabilities
    if server.status == "connected" and server.capabilities and view.expanded_server == server.name then
        -- local desc = server.description or ""
        -- if desc ~= "" then
        --     table.insert(lines, Text.pad_line(NuiLine():append(tostring(desc), Text.highlights.muted), nil, 5))
        --     current_line = current_line + 1
        -- end

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
            return current_line
        end

        local custom_instructions = server_config.custom_instructions or {}
        local is_disabled = custom_instructions.disabled == true
        local has_instructions = custom_instructions.text and #custom_instructions.text > 0
        local ci_line = NuiLine()
            :append(is_disabled and Text.icons.circle or Text.icons.instructions, Text.highlights.muted)
            :append(
                " Custom Instructions" .. (not is_disabled and not has_instructions and " (empty)" or ""),
                (is_disabled or not has_instructions) and Text.highlights.muted or Text.highlights.info
            )
        table.insert(lines, Text.pad_line(ci_line, nil, 5))
        current_line = current_line + 1
        view:track_line(current_line, "customInstructions", {
            server_name = server.name,
            disabled = is_disabled,
            name = Text.icons.instructions .. " Custom Instructions",
            hint = is_disabled and "[<t> Toggle]" or "[<e> Edit, <t> Toggle]",
        })
        table.insert(lines, Text.empty_line())
        current_line = current_line + 1

        if #server.capabilities.prompts > 0 then
            local section_lines, new_line, mappings =
                M.render_cap_section(server.capabilities.prompts, "Prompts", server.name, "prompt", current_line)
            vim.list_extend(lines, section_lines)
            for _, m in ipairs(mappings) do
                view:track_line(m.line, m.type, m.context)
            end
            table.insert(lines, Text.empty_line())
            current_line = new_line + 1
        end
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
    local is_native = native.is_native_server(server.name)
    local server_config = (is_native and State.native_servers_config[server.name] or State.servers_config[server.name])
        or {}
    local is_enabled = server_config.disabled ~= true
    if is_native and not is_enabled then
        server.status = "disabled"
    end
    local status = M.get_server_status_info(server.status, active)
    local line = NuiLine()
    local hl = server.status == "connected" and Text.highlights.success or status.hl
    line:append(status.icon, status.hl)
    line:append(server.displayName or server.name, hl)
    if server.transportType == "sse" then
        line:append(" " .. (server.status == "connected" and Text.icons.sse or Text.icons.sse), hl)
    else
    end

    --INFO: when decoded from regualr mcp servers vim.NIL; for nativeservers we set nil, so check both
    -- Add error message for disconnected servers
    if server.error ~= vim.NIL and server.error ~= nil and server.status == "disconnected" and server.error ~= "" then
        -- Get first line of error message
        local error_lines = Text.multiline(server.error, Text.highlights.error)
        line:append(" - ", Text.highlights.muted):append(error_lines[1], Text.highlights.error)
    end

    -- Add capabilities counts inline for connected servers
    if server.status == "connected" and server.capabilities then
        local custom_instructions = server_config.custom_instructions
        if custom_instructions and custom_instructions.text and custom_instructions.text ~= "" then
            local is_disabled = server_config.custom_instructions.disabled
            line:append(
                " " .. Text.icons.instructions .. " ",
                is_disabled and Text.highlights.muted or Text.highlights.success
            )
        end
        -- Show auto-approve status for server using smart detection
        local all_tools = {}
        for _, tool in ipairs(server.capabilities.tools or {}) do
            table.insert(all_tools, tool.name)
        end

        local auto_approve = server_config.autoApprove
        local status = "none"
        local count = 0

        if auto_approve == true then
            status = "all"
            count = #all_tools
        elseif type(auto_approve) == "table" and vim.islist(auto_approve) then
            if #auto_approve == 0 then
                status = "none"
                count = 0
            elseif #auto_approve == #all_tools and #all_tools > 0 then
                status = "all"
                count = #all_tools
            else
                status = "partial"
                count = #auto_approve
            end
        end

        if status == "all" then
            -- All tools auto-approved
            line:append(" " .. Text.icons.auto .. " ", Text.highlights.success)
        elseif status == "partial" then
            -- Partial auto-approval (show count)
            line:append(" " .. Text.icons.auto .. " " .. tostring(count) .. " ", Text.highlights.warning)
        end

        -- Helper to render capability count with active/total
        local function render_capability_count(capabilities, disabled_list, id_field, icon, highlight)
            if capabilities and #capabilities > 0 then
                local current_ids = vim.tbl_map(function(cap)
                    return cap[id_field]
                end, capabilities)
                local disabled = vim.tbl_filter(function(item)
                    return vim.tbl_contains(current_ids, item)
                end, disabled_list or {})
                local enabled = #capabilities - #disabled

                line:append(icon, highlight):append(
                    (" " .. tostring(enabled) .. (#disabled > 0 and "/" .. tostring(#capabilities) or "")),
                    Text.highlights.muted
                )
                return true
            end
        end
        -- line:append(" [", Text.highlights.muted)

        -- if
        --     render_capability_count(
        --         server.capabilities.prompts,
        --         server_config.disabled_prompts,
        --         "name",
        --         Text.icons.prompt,
        --         Text.highlights.muted
        --     )
        -- then
        --     line:append(" ")
        -- end
        -- render_capability_count(
        --     server.capabilities.tools,
        --     server_config.disabled_tools,
        --     "name",
        --     Text.icons.tool,
        --     Text.highlights.success
        -- )
        -- line:append(" ")
        -- render_capability_count(
        --     server.capabilities.resources,
        --     server_config.disabled_resources,
        --     "uri",
        --     Text.icons.resource,
        --     Text.highlights.warning
        -- )
        -- line:append(" ")
        -- render_capability_count(
        --     server.capabilities.resourceTemplates,
        --     server_config.disabled_resourceTemplates,
        --     "uriTemplate",
        --     Text.icons.resourceTemplate,
        --     Text.highlights.error
        -- )
        -- line:append("]", Text.highlights.muted)
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
---@param error_type? string Optional error type to filter (setup/server/runtime)
---@param detailed? boolean Whether to show full error details
---@return NuiLine[] Lines
function M.render_hub_errors(error_type, detailed)
    local lines = {}
    local errors = State:get_errors(error_type)
    if #errors > 0 then
        for _, err in ipairs(errors) do
            vim.list_extend(lines, M.render_error(err, detailed))
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

function M.render_error(err, detailed)
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
