---@brief [[
--- Main dashboard view for MCPHub
--- Shows server status and connected servers
---@brief ]]
local Capabilities = require("mcphub.ui.capabilities")
local NuiLine = require("mcphub.utils.nuiline")
local State = require("mcphub.state")
local Text = require("mcphub.utils.text")
local View = require("mcphub.ui.views.base")
local renderer = require("mcphub.utils.renderer")
local utils = require("mcphub.utils")

---@class MainView
---@field super View
---@field expanded_server string|nil Currently expanded server name
---@field active_capability CapabilityHandler|nil Currently active capability
---@field cursor_positions {browse_mode: number[]|nil, capability_line: number[]|nil} Cursor positions for different modes
local MainView = setmetatable({}, {
    __index = View,
})
MainView.__index = MainView

function MainView:new(ui)
    local self = View:new(ui, "main") -- Create base view with name
    self = setmetatable(self, MainView)

    -- Initialize state
    self.expanded_server = nil
    self.active_capability = nil
    self.cursor_positions = {
        browse_mode = nil, -- Will store [line, col]
        capability_line = nil, -- Will store [line, col]
    }

    return self
end

function MainView:handle_action()
    local go_to_cap_line = false
    -- Get current line
    local cursor = vim.api.nvim_win_get_cursor(0)
    local line = cursor[1]

    -- Get line info
    local type, context = self:get_line_info(line)
    if type == "server" then
        -- Toggle expand/collapse for server
        if context.status == "connected" then
            if self.expanded_server == context.name then
                self.expanded_server = nil -- collapse
                self:draw()
            else
                -- When expanding new server
                local prev_expanded = self.expanded_server
                self.expanded_server = context.name -- expand
                self:draw()

                -- Find server and capabilities in new view
                local server_line = nil
                local first_cap_line = nil

                for _, tracked in ipairs(self.interactive_lines) do
                    if tracked.type == "server" and tracked.context.name == context.name then
                        server_line = tracked.line
                    elseif
                        tracked.type == "tool"
                        or tracked.type == "resource"
                        or tracked.type == "resourceTemplate"
                        or tracked.type == "customInstructions"
                    then
                        if tracked.context.server_name == context.name and not first_cap_line then
                            first_cap_line = tracked.line
                            break
                        end
                    end
                end

                -- Position cursor:
                -- 1. On first capability if exists
                -- 2. Otherwise on server line
                -- 3. Fallback to current line
                if first_cap_line and go_to_cap_line then
                    vim.api.nvim_win_set_cursor(0, { first_cap_line, 3 })
                elseif server_line then
                    vim.api.nvim_win_set_cursor(0, { server_line, 3 })
                else
                    vim.api.nvim_win_set_cursor(0, { line, 3 })
                end
            end
        end
    elseif
        (type == "tool" or type == "resource" or type == "resourceTemplate" or type == "customInstructions") and context
    then
        -- Check if tool is disabled
        local is_tool_disabled = false
        if type == "tool" then
            local server_config = State.servers_config[context.server_name] or {}
            local disabled_tools = server_config.disabled_tools or {}
            is_tool_disabled = vim.tbl_contains(disabled_tools, context.name)
            if is_tool_disabled then
                return
            end
        end
        if type == "customInstructions" then
            local is_disabled = context.disabled
            if is_disabled then
                return
            end
        end

        -- Store browse mode position before entering capability
        self.cursor_positions.browse_mode = vim.api.nvim_win_get_cursor(0)

        -- Create capability handler and switch to capability mode
        self.active_capability = Capabilities.create_handler(type, context.server_name, context, self)
        self:setup_active_mode()
        self:draw()

        -- Move to capability's preferred position
        local cap_pos = self.active_capability:get_cursor_position()
        if cap_pos then
            vim.api.nvim_win_set_cursor(0, cap_pos)
        end
    end
end

function MainView:setup_active_mode()
    if self.active_capability then
        self.keymaps = {
            ["<CR>"] = {
                action = function()
                    if self.active_capability.handle_action then
                        self.active_capability:handle_action(vim.api.nvim_win_get_cursor(0)[1])
                    end
                end,
                desc = "Execute/Submit",
            },
            ["<Esc>"] = {
                action = function()
                    -- Store capability line before exiting
                    self.cursor_positions.capability_line = vim.api.nvim_win_get_cursor(0)

                    -- Clear active capability
                    self.active_capability = nil

                    -- Setup browse mode and redraw
                    self:setup_active_mode()
                    self:draw()

                    -- Restore to last browse mode position
                    if self.cursor_positions.browse_mode then
                        vim.api.nvim_win_set_cursor(0, self.cursor_positions.browse_mode)
                    end
                end,
                desc = "Back",
            },
        }
    else
        -- Normal mode keymaps
        self.keymaps = {
            ["t"] = {
                action = function()
                    self:handle_server_toggle()
                end,
                desc = "Toggle server",
            },
            ["<CR>"] = {
                action = function()
                    self:handle_action()
                end,
                desc = "Expand/Collapse",
            },
        }
    end
    self:apply_keymaps()
end

function MainView:handle_server_toggle()
    -- Get current line
    local cursor = vim.api.nvim_win_get_cursor(0)
    local line = cursor[1]

    -- Get line info
    local type, context = self:get_line_info(line)
    if type == "server" and context then
        -- Toggle server state
        if State.hub_instance then
            if context.status == "disabled" then
                vim.notify("Enabling server: " .. context.name)
                State.hub_instance:start_mcp_server(context.name, {
                    callback = function(response, err)
                        -- if err then
                        --     vim.notify("Failed to enable server: " .. err, vim.log.levels.ERROR)
                        -- end
                    end,
                })
            else
                vim.notify("Disabling server: " .. context.name)
                State.hub_instance:stop_mcp_server(context.name, true, {
                    callback = function(response, err)
                        if err then
                            vim.notify("Failed to disable server: " .. err, vim.log.levels.ERROR)
                        end
                    end,
                })
            end
        end
    elseif type == "tool" and context then
        -- Toggle tool state
        if State.hub_instance then
            local server_config = State.servers_config[context.server_name] or {}
            local disabled_tools = server_config.disabled_tools or {}
            local is_disabled = vim.tbl_contains(disabled_tools, context.name)

            if is_disabled then
                vim.notify("Enabling tool: " .. context.name)
            else
                vim.notify("Disabling tool: " .. context.name)
            end

            State.hub_instance:update_tool_config(context.server_name, context.name, not is_disabled)
            -- self:draw()
        end
    elseif type == "customInstructions" and context then
        -- Toggle custom instructions state
        if State.hub_instance then
            local server_config = State.servers_config[context.server_name] or {}
            local custom_instructions = server_config.custom_instructions or {}
            local is_disabled = custom_instructions.disabled

            if is_disabled then
                vim.notify("Enabling custom instructions for: " .. context.server_name)
            else
                vim.notify("Disabling custom instructions for: " .. context.server_name)
            end

            State.hub_instance:update_server_config(context.server_name, {
                custom_instructions = vim.tbl_extend("force", custom_instructions, {
                    disabled = not is_disabled,
                }),
            })
            -- self:draw()
        end
    end
end

function MainView:get_initial_cursor_position()
    -- Position after server status section
    local lines = self:render_header()
    vim.list_extend(lines, self:render_hub_status(self:get_width()))
    -- In browse mode, restore last browse position
    if not self.active_capability and self.cursor_positions.browse_mode then
        return self.cursor_positions.browse_mode[1]
    end
    return #lines + 1
end

--- Render server status section
---@return NuiLine[]
function MainView:render_hub_status()
    local lines = {}
    -- Server state header and status
    local status = renderer.get_server_status_info(State.server_state.status)
    local status_line = NuiLine():append(status.icon, status.hl):append(({
        connected = "Connected",
        connecting = "Connecting...",
        disconnected = "Disconnected",
    })[State.server_state.status] or "Unknown", status.hl)

    if State.server_state.started_at then
        status_line:append(" " .. utils.format_relative_time(State.server_state.started_at), Text.highlights.muted)
    end
    table.insert(lines, Text.pad_line(status_line))
    table.insert(lines, self:divider())
    if State.server_state.status ~= "connected" then
        vim.list_extend(lines, renderer.render_server_entries(State.server_output.entries, false))
    end
    table.insert(lines, Text.empty_line())
    return lines
end

--- Sort servers by status (connected first, then disconnected, disabled last) and alphabetically within each group
---@param servers table[] List of servers to sort
local function sort_servers(servers)
    table.sort(servers, function(a, b)
        -- First compare status priority
        local status_priority = {
            connected = 1,
            disconnected = 2,
            disabled = 3,
        }
        local a_priority = status_priority[a.status] or 2 -- default to disconnected priority
        local b_priority = status_priority[b.status] or 2

        if a_priority ~= b_priority then
            return a_priority < b_priority
        end

        -- If same status, sort alphabetically
        return a.name < b.name
    end)
    return servers
end

--- Render server capabilities section
---@param items table[] List of items
---@param title string Section title
---@param server_name string Server name
---@param type string Item type
---@param current_line number Current line number
---@return NuiLine[],number,table[] Lines, new current line, mappings
local function render_cap_section(items, title, server_name, type, current_line)
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

    if type == "tool" then
        -- For tools, sort by name and move disabled ones to end
        local sorted_items = vim.deepcopy(items)
        local server_config = State.servers_config[server_name] or {}
        local disabled_tools = server_config.disabled_tools or {}

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
        local is_disabled = false
        if type == "tool" then
            local server_config = State.servers_config[server_name] or {}
            local disabled_tools = server_config.disabled_tools or {}
            is_disabled = vim.tbl_contains(disabled_tools, item.name)
        end

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
                hint = hint,
            }),
        })
    end

    return lines, current_line + #lines, mappings
end

--- Render connected servers section
---@return NuiLine[]
function MainView:render_servers(line_offset)
    local lines = {}
    local current_line = line_offset

    -- Section header with token information
    local header_line = NuiLine():append("MCP Servers", Text.highlights.title)

    -- Add token count if connected
    if State.server_state.status == "connected" and State.hub_instance and State.hub_instance:is_ready() then
        local prompts = State.hub_instance:get_prompts()
        if prompts then
            -- Calculate total tokens from all prompts
            local active_servers_tokens = utils.calculate_tokens(prompts.active_servers or "")
            local use_mcp_tool_tokens = utils.calculate_tokens(prompts.use_mcp_tool or "")
            local access_mcp_resource_tokens = utils.calculate_tokens(prompts.access_mcp_resource or "")
            local total_tokens = active_servers_tokens + use_mcp_tool_tokens + access_mcp_resource_tokens

            if total_tokens > 0 then
                header_line:append(
                    " (~ " .. utils.format_token_count(total_tokens) .. " tokens)",
                    Text.highlights.muted
                )
            end
        end
    end

    table.insert(lines, Text.pad_line(header_line))
    current_line = current_line + 1
    table.insert(lines, self:divider())
    current_line = current_line + 1

    if not State.server_state.servers or #State.server_state.servers == 0 then
        -- No servers connected
        table.insert(lines, Text.pad_line(NuiLine():append("No servers connected", Text.highlights.muted)))
        table.insert(lines, Text.empty_line())
        current_line = current_line + 1
        return lines
    end
    -- Sort servers (enabled first)
    local sorted_servers = sort_servers(vim.deepcopy(State.server_state.servers))

    -- Function to render a single server's capabilities
    local function render_server_capabilities(server, lines, current_line, config_source, view)
        local server_name_line = renderer.render_server_line(server, view.expanded_server == server.name)
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
            local ci_line = NuiLine()
                :append(is_disabled and Text.icons.circle or Text.icons.arrowRight, Text.highlights.muted)
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
                hint = is_disabled and "Press 't' to enable instructions" or "Press <CR> to edit, 't' to disable",
            })
            table.insert(lines, Text.empty_line())
            current_line = current_line + 1

            -- Tools section if any
            if #server.capabilities.tools > 0 then
                local section_lines, new_line, mappings =
                    render_cap_section(server.capabilities.tools, "Tools", server.name, "tool", current_line)
                vim.list_extend(lines, section_lines)
                for _, m in ipairs(mappings) do
                    view:track_line(m.line, m.type, m.context)
                end
                table.insert(lines, Text.empty_line())
                current_line = new_line + 1
            end

            -- Resources section if any
            if #server.capabilities.resources > 0 then
                local section_lines, new_line, mappings = render_cap_section(
                    server.capabilities.resources,
                    "Resources",
                    server.name,
                    "resource",
                    current_line
                )
                vim.list_extend(lines, section_lines)
                for _, m in ipairs(mappings) do
                    view:track_line(m.line, m.type, m.context)
                end
                table.insert(lines, Text.empty_line())
                current_line = new_line + 1
            end

            -- Resource Templates section if any
            if #server.capabilities.resourceTemplates > 0 then
                local section_lines, new_line, mappings = render_cap_section(
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

    -- Render regular MCP servers
    for _, server in ipairs(sorted_servers) do
        current_line = render_server_capabilities(server, lines, current_line, State.servers_config, self)
    end

    -- Add native servers section if any
    if #State.server_state.native_servers > 0 then
        table.insert(lines, Text.empty_line())
        current_line = current_line + 1
        table.insert(lines, Text.pad_line(NuiLine():append("Native Servers", Text.highlights.title)))
        current_line = current_line + 1

        local sorted_native = sort_servers(vim.deepcopy(State.server_state.native_servers))
        for _, server in ipairs(sorted_native) do
            current_line = render_server_capabilities(server, lines, current_line, State.native_server_config, self)
        end
    end

    return lines
end

function MainView:before_enter()
    View.before_enter(self)
    self:setup_active_mode()
end

function MainView:after_enter()
    View.after_enter(self)

    local line_count = vim.api.nvim_buf_line_count(self.ui.buffer)
    -- Restore appropriate cursor position
    if self.active_capability then
        local cap_pos = self.active_capability:get_cursor_position()
        if cap_pos then
            local new_pos = { math.min(cap_pos[1], line_count), cap_pos[2] }
            vim.api.nvim_win_set_cursor(0, new_pos)
        end
    else
        -- In browse mode, restore last browse position with column
        if self.cursor_positions.browse_mode then
            local new_pos = {
                math.min(self.cursor_positions.browse_mode[1], line_count),
                self.cursor_positions.browse_mode[2],
            }
            vim.api.nvim_win_set_cursor(0, new_pos)
        end
    end
end

function MainView:before_leave()
    -- Store appropriate position based on current mode
    if self.active_capability then
        -- In capability mode, store full position
        self.cursor_positions.capability_line = vim.api.nvim_win_get_cursor(0)
    else
        -- In browse mode, store full position
        self.cursor_positions.browse_mode = vim.api.nvim_win_get_cursor(0)
    end

    View.before_leave(self)
end

function MainView:render()
    -- Handle special states from base view
    if State.setup_state == "failed" or State.setup_state == "in_progress" then
        return View.render(self)
    end
    -- Get base header
    local lines = self:render_header(false)
    if State.server_state.status ~= "connected" then
        -- Server status section
        vim.list_extend(lines, self:render_hub_status())
        return lines
    end
    -- Handle capability mode
    if self.active_capability then
        -- Get base header
        local capability_view_lines = self:render_header(false)
        -- Add breadcrumb
        local breadcrumb = NuiLine()
            :append(self.active_capability.server_name, Text.highlights.muted)
            :append(" > ", Text.highlights.muted)
            :append(" " .. self.active_capability.info.name .. " ", Text.highlights.info)
        table.insert(capability_view_lines, Text.pad_line(breadcrumb))
        table.insert(capability_view_lines, self:divider())
        -- Let capability render its content
        vim.list_extend(capability_view_lines, self.active_capability:render(#capability_view_lines))
        return capability_view_lines
    end

    -- Servers section
    vim.list_extend(lines, self:render_servers(#lines))
    -- Recent errors section (show compact view without details)
    table.insert(lines, Text.empty_line())
    table.insert(lines, Text.empty_line())
    table.insert(lines, Text.pad_line(NuiLine():append("Recent Issues", Text.highlights.title)))
    local errors = renderer.render_hub_errors(nil, false)
    if #errors > 0 then
        vim.list_extend(lines, errors)
    else
        table.insert(lines, Text.pad_line(NuiLine():append("No recent issues", Text.highlights.muted)))
    end
    return lines
end

return MainView
