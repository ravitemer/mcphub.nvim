---@brief [[
--- Main dashboard view for MCPHub
--- Shows server status and connected servers
---@brief ]]
local Capabilities = require("mcphub.ui.capabilities")
local NuiLine = require("mcphub.utils.nuiline")
local State = require("mcphub.state")
local Text = require("mcphub.utils.text")
local View = require("mcphub.ui.views.base")
local native = require("mcphub.native")
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

function MainView:show_prompts_view()
    -- Store current cursor position before switching
    self.cursor_positions.browse_mode = vim.api.nvim_win_get_cursor(0)

    -- Switch to prompts capability
    self.active_capability = Capabilities.create_handler("prompts", "MCP Servers", { name = "System Prompts" }, self)
    self:setup_active_mode()
    self:draw()
    -- Move to capability's preferred position
    local cap_pos = self.active_capability:get_cursor_position()
    if cap_pos then
        vim.api.nvim_win_set_cursor(0, cap_pos)
    end
end

function MainView:handle_action()
    local go_to_cap_line = false
    -- Get current line
    local cursor = vim.api.nvim_win_get_cursor(0)
    local line = cursor[1]

    -- Get line info
    local type, context = self:get_line_info(line)
    if type == "breadcrumb" then
        self:show_prompts_view()
    elseif type == "server" then
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
    elseif type == "create_server" then
        -- Store browse mode position before switching
        self.cursor_positions.browse_mode = vim.api.nvim_win_get_cursor(0)

        -- Switch to create server capability
        self.active_capability =
            Capabilities.create_handler("createServer", "Native Servers", { name = "Create Server" }, self)
        self:setup_active_mode()
        self:draw()
        -- Move to capability's preferred position
        local cap_pos = self.active_capability:get_cursor_position()
        if cap_pos then
            vim.api.nvim_win_set_cursor(0, cap_pos)
        end
    elseif
        (type == "tool" or type == "resource" or type == "resourceTemplate" or type == "customInstructions") and context
    then
        if context.disabled then
            return
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
            ["gd"] = {
                action = function()
                    self:show_prompts_view()
                end,
                desc = "View prompts",
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
    if type == "server" and context and State.hub_instance then
        -- Handle regular MCP server
        if context.status == "disabled" then
            State.hub_instance:start_mcp_server(context.name, {
                callback = function(response, err)
                    if err then
                        vim.notify("Failed to enable server: " .. err, vim.log.levels.ERROR)
                    end
                end,
            })
        else
            State.hub_instance:stop_mcp_server(context.name, true, {
                callback = function(response, err)
                    if err then
                        vim.notify("Failed to disable server: " .. err, vim.log.levels.ERROR)
                    end
                end,
            })
        end
    elseif type == "tool" and context and State.hub_instance then
        local server_name = context.server_name
        local is_native = native.is_native_server(server_name)
        local tool_name = context.def.name
        local server_config = (
            is_native and State.native_servers_config[server_name] or State.servers_config[server_name]
        ) or {}
        local disabled_tools = vim.deepcopy(server_config.disabled_tools or {})
        local is_disabled = vim.tbl_contains(disabled_tools, tool_name)

        -- Update disabled_tools list based on desired state
        if is_disabled then
            for i, name in ipairs(disabled_tools) do
                if name == tool_name then
                    table.remove(disabled_tools, i)
                    break
                end
            end
        else
            table.insert(disabled_tools, tool_name)
        end
        State.hub_instance:update_server_config(server_name, {
            disabled_tools = disabled_tools,
        })
    elseif type == "customInstructions" and context then
        -- Toggle custom instructions state
        local server_name = context.server_name
        local is_native = native.is_native_server(server_name)
        local server_config = (
            is_native and State.native_servers_config[server_name] or State.servers_config[server_name]
        ) or {}
        local custom_instructions = server_config.custom_instructions or {}
        local is_disabled = custom_instructions.disabled

        State.hub_instance:update_server_config(server_name, {
            custom_instructions = {
                disabled = not is_disabled,
            },
        })
    end
end

function MainView:get_initial_cursor_position()
    -- Position after server status section
    local lines = self:render_header(false)
    -- vim.list_extend(lines, self:render_hub_status(self:get_width()))
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

--- Render a server section
---@param title string Section title
---@param servers table[] List of servers
---@param config_source table Config source for the servers
---@param current_line number Current line number
---@return NuiLine[], number Lines and new current line
function MainView:render_servers_section(title, servers, config_source, current_line)
    local lines = {}

    if title then
        -- Section header
        table.insert(lines, Text.pad_line(NuiLine():append(title, Text.highlights.title)))
        current_line = current_line + 1
    end

    -- If no servers in section
    if not servers or #servers == 0 then
        table.insert(
            lines,
            Text.pad_line(
                NuiLine():append("No servers connected " .. "(Install from Marketplace)", Text.highlights.muted)
            )
        )
        table.insert(lines, Text.empty_line())
        return lines, current_line + 2
    end

    -- Sort and render servers
    local sorted = sort_servers(vim.deepcopy(servers))
    for _, server in ipairs(sorted) do
        current_line = renderer.render_server_capabilities(server, lines, current_line, config_source, self)
    end

    return lines, current_line
end

--- Render all server sections
---@return NuiLine[]
function MainView:render_servers(line_offset)
    local lines = {}
    local current_line = line_offset

    -- Start with top-level MCP Servers header
    local header_line = NuiLine():append("MCP Servers", Text.highlights.title)

    -- Add token count on MCP Servers section if connected
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
    -- Track breadcrumb line for interaction
    self:track_line(current_line, "breadcrumb", {
        hint = "Press <CR> to preview system prompts",
    })
    table.insert(lines, self:divider())
    current_line = current_line + 1

    -- Render MCP servers section (without title since we already added it)
    local mcp_lines, new_line =
        self:render_servers_section(nil, State.server_state.servers, State.servers_config, current_line)
    vim.list_extend(lines, mcp_lines)
    current_line = new_line

    -- Add spacing between sections
    table.insert(lines, Text.empty_line())
    current_line = current_line + 1

    -- Native servers section header
    table.insert(lines, Text.pad_line(NuiLine():append("Native Servers", Text.highlights.title)))
    current_line = current_line + 1

    -- Render Native servers first
    local native_lines, native_line = self:render_servers_section(
        nil, -- No title since we added it above
        State.server_state.native_servers,
        State.native_servers_config,
        current_line
    )
    vim.list_extend(lines, native_lines)
    current_line = native_line

    -- Add create server option
    -- table.insert(lines, Text.empty_line())
    table.insert(
        lines,
        Text.pad_line(
            NuiLine()
                :append(" " .. Text.icons.edit .. " ", Text.highlights.muted)
                :append("Auto Create Server", Text.highlights.muted)
        )
    )
    -- Track line for interaction
    self:track_line(current_line + 1, "create_server", {
        hint = "Press <CR> to create server",
    })

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
                self.cursor_positions.browse_mode[2] or 2,
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
        breadcrumb
            :append(self.active_capability.server_name, Text.highlights.muted)
            :append(" > ", Text.highlights.muted)
            :append(self.active_capability.name, Text.highlights.info)
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
