---@brief [[
--- Main dashboard view for MCPHub
--- Shows server status and connected servers
---@brief ]]
local Capabilities = require("mcphub.ui.capabilities")
local NuiLine = require("mcphub.utils.nuiline")
local State = require("mcphub.state")
local Text = require("mcphub.utils.text")
local View = require("mcphub.ui.views.base")
local constants = require("mcphub.utils.constants")
local native = require("mcphub.native")
local renderer = require("mcphub.utils.renderer")
local ui_utils = require("mcphub.utils.ui")
local utils = require("mcphub.utils")
local validation = require("mcphub.utils.validation")

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
    self.active_capability = Capabilities.create_handler("preview", "MCP Servers", { name = "System Prompts" }, self)
    self:setup_active_mode()
    self:draw()
    -- Move to capability's preferred position
    local cap_pos = self.active_capability:get_cursor_position()
    if cap_pos then
        vim.api.nvim_win_set_cursor(0, cap_pos)
    end
end

function MainView:handle_collapse()
    -- Get current line
    local cursor = vim.api.nvim_win_get_cursor(0)
    local line = cursor[1]

    -- Get line info
    local type, context = self:get_line_info(line)

    -- If we're on a server line, handle directly
    if type == "server" then
        if context.status == "connected" and self.expanded_server == context.name then
            local server_line = line
            self.expanded_server = nil -- collapse
            self:draw()
            vim.api.nvim_win_set_cursor(0, { server_line, 3 })
            return
        end
    end

    -- If we have an expanded server, determine if we're in its scope
    if self.expanded_server then
        local expanded_server_line
        local next_server_line

        -- Find the expanded server's line and next server's line
        for i, tracked in ipairs(self.interactive_lines) do
            if tracked.type == "server" then
                if tracked.context.name == self.expanded_server then
                    expanded_server_line = tracked.line
                elseif expanded_server_line and not next_server_line then
                    -- This is the next server after our expanded one
                    next_server_line = tracked.line
                    break
                end
            end
        end

        -- Check if current line is within expanded server's section:
        -- After expanded server line and before next server (or end if no next server)
        if
            expanded_server_line
            and line > expanded_server_line
            and (not next_server_line or line < next_server_line)
        then
            self.expanded_server = nil
            self:draw()
            vim.api.nvim_win_set_cursor(0, { expanded_server_line, 3 })
        end
    end
end

function MainView:handle_custom_instructions(context)
    -- Get current instructions
    local is_native = native.is_native_server(context.server_name)
    local server_config = (
        is_native and State.native_servers_config[context.server_name] or State.servers_config[context.server_name]
    ) or {}
    local custom_instructions = server_config.custom_instructions or {}
    local text = custom_instructions.text or ""

    -- Open text box using base class method
    ui_utils.multiline_input("Custom Instructions", text, function(content)
        if content ~= text then
            State.hub_instance:update_server_config(context.server_name, {
                custom_instructions = vim.tbl_extend("force", custom_instructions, { text = content }),
            })
            vim.notify("Updated custom instructions for " .. context.server_name, vim.log.levels.INFO)
        end
    end, {
        filetype = "markdown",
        start_insert = false,
        show_footer = false,
    })
end

function MainView:add_server()
    ui_utils.multiline_input("Paste server's json config", "", function(content)
        if not content or vim.trim(content) == "" then
            return
        end
        --validated in validate field
        local name, config = utils.parse_config_from_json(content)
        State.hub_instance:update_server_config(name, config)
        vim.notify("Server " .. name .. " added successfully", vim.log.levels.INFO)
    end, {
        filetype = "json",
        start_insert = true,
        show_footer = false,
        --instead of closing the input, validate and show errors
        validate = function(content)
            local name, config = utils.parse_config_from_json(content)
            if not name then
                vim.notify(config, vim.log.levels.ERROR)
                return false
            end
            local valid = validation.validate_server_config(name, config)
            if not valid.ok then
                vim.notify(valid.error.message, vim.log.levels.ERROR)
                return false
            end
            return true
        end,
    })
end

function MainView:handle_edit()
    -- Get current line
    local cursor = vim.api.nvim_win_get_cursor(0)
    local line = cursor[1]

    local type, context = self:get_line_info(line)
    local server_name = context.name
    if type == "server" then
        local is_native = native.is_native_server(server_name)
        if is_native then
            return vim.notify("Native servers cannot be edited")
        end
        local config = State.servers_config[server_name] or {}
        local text = utils.pretty_json(vim.json.encode({
            [server_name] = config,
        }))
        ui_utils.multiline_input("Edit '" .. server_name .. "' Config", text, function(input)
            if text == input then
                return
            end
            local new_name, new_config = next(vim.json.decode(input))
            if new_name ~= server_name then
                State.hub_instance:remove_server_config(server_name)
                vim.notify("Server " .. server_name .. " deleted", vim.log.levels.INFO)
            end
            State.hub_instance:update_server_config(new_name, new_config, { merge = false })
            vim.notify("Server " .. new_name .. " updated", vim.log.levels.INFO)
        end, {
            filetype = "json",
            start_insert = false,
            show_footer = false,
            --instead of closing the input, validate and show errors
            validate = function(content)
                local success, result = pcall(vim.json.decode, content)
                if not success then
                    vim.notify("Invalid JSON: " .. result, vim.log.levels.ERROR)
                    return
                end
                -- Case 3: Single server name:config pair
                -- {
                --   "server_name": {}
                -- }
                if vim.tbl_count(result) ~= 1 then
                    vim.notify("Config should have exactly one key i.e server name", vim.log.levels.ERROR)
                    return false
                end
                local new_name, new_config = next(result)
                local valid = validation.validate_server_config(new_name, new_config)
                if not valid.ok then
                    vim.notify(valid.error.message, vim.log.levels.ERROR)
                    return false
                end
                return true
            end,
        })
    elseif (type == "customInstructions") and context then
        self:handle_custom_instructions(context)
    end
end

function MainView:handle_delete()
    -- Get current line
    local cursor = vim.api.nvim_win_get_cursor(0)
    local line = cursor[1]

    local type, context = self:get_line_info(line)
    if type == "server" then
        local server_name = context.name
        local is_native = native.is_native_server(server_name)
        if is_native then
            return vim.notify("Native servers cannot be deleted")
        end
        --confirm deletion
        local confirm = vim.fn.confirm("Are you sure you want to delete " .. server_name .. "?", "&Yes\n&No", 2)
        if confirm == 1 then
            State.hub_instance:remove_server_config(server_name)
            vim.notify("Server " .. server_name .. " deleted", vim.log.levels.INFO)
        end
    end
end

function MainView:handle_action(line_override, context_override)
    local go_to_cap_line = false
    -- Get current line
    local cursor = vim.api.nvim_win_get_cursor(0)
    local line = line_override or cursor[1]

    -- Get line info from either override or current line
    local type, context
    if context_override then
        type = context_override.type
        context = context_override.context
    else
        type, context = self:get_line_info(line)
    end
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

        -- Switch to createServer or addServer capability
        if type == "create_server" then
            self.active_capability =
                Capabilities.create_handler("createServer", "Native Servers", { name = "Create Server" }, self)
        end
        self:setup_active_mode()
        self:draw()
        -- Move to capability's preferred position
        local cap_pos = self.active_capability:get_cursor_position()
        if cap_pos then
            vim.api.nvim_win_set_cursor(0, cap_pos)
        end
    elseif (type == "tool" or type == "resource" or type == "resourceTemplate" or type == "prompt") and context then
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
    elseif (type == "customInstructions") and context then
        self:handle_custom_instructions(context)
    elseif type == "add_server" then
        self:add_server()
    end
end

function MainView:handle_cursor_move()
    -- Clear previous highlight
    if self.cursor_highlight then
        vim.api.nvim_buf_del_extmark(self.ui.buffer, self.hover_ns, self.cursor_highlight)
        self.cursor_highlight = nil
    end

    -- Get current line
    local cursor = vim.api.nvim_win_get_cursor(0)
    local line = cursor[1]
    if self.active_capability then
        self.active_capability:handle_cursor_move(self, line)
    else
        -- Get line info
        local type, context = self:get_line_info(line)
        if type then
            -- Add virtual text without line highlight
            self.cursor_highlight = vim.api.nvim_buf_set_extmark(self.ui.buffer, self.hover_ns, line - 1, 0, {
                virt_text = { { context and context.hint or "[<l> Interact]", Text.highlights.muted } },
                virt_text_pos = "eol",
            })
        end
    end
end

function MainView:setup_active_mode()
    if self.active_capability then
        self.keymaps = {
            ["l"] = {
                action = function()
                    if self.active_capability.handle_action then
                        self.active_capability:handle_action(vim.api.nvim_win_get_cursor(0)[1])
                    end
                end,
                desc = "Execute/Submit",
            },
            ["o"] = {
                action = function()
                    if self.active_capability.handle_text_box then
                        self.active_capability:handle_text_box(vim.api.nvim_win_get_cursor(0)[1])
                    end
                end,
                desc = "Open text box",
            },
            ["<Tab>"] = {
                action = function()
                    if self.active_capability.handle_tab then
                        self.active_capability:handle_tab()
                    end
                end,
                desc = "Switch tab",
            },
            ["h"] = {
                action = function()
                    -- -- Store capability line before exiting
                    -- self.cursor_positions.capability_line = vim.api.nvim_win_get_cursor(0)

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
            ["e"] = {
                action = function()
                    self:handle_edit()
                end,
                desc = "Edit",
            },
            ["d"] = {
                action = function()
                    self:handle_delete()
                end,
                desc = "Delete",
            },

            ["A"] = {
                action = function()
                    -- Handle like an add_server action
                    self:add_server()
                end,
                desc = "Add Server",
            },
            ["t"] = {
                action = function()
                    self:handle_server_toggle()
                end,
                desc = "Toggle",
            },
            ["h"] = {
                action = function()
                    self:handle_collapse()
                end,
                desc = "Collapse",
            },
            ["l"] = {
                action = function()
                    self:handle_action()
                end,
                desc = "Expand",
            },
            ["gd"] = {
                action = function()
                    self:show_prompts_view()
                end,
                desc = "Preview",
            },
        }
    end
    self.keymaps["ga"] = {
        action = function()
            vim.g.mcphub_auto_approve = not vim.g.mcphub_auto_approve
            self:draw()
        end,
        desc = "Toggle AutoApprove",
    }
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
        -- Gets updated via sse endpoint after file changed rather than explicitly send curl request
        if context.status == "disabled" then
            State.hub_instance:start_mcp_server(context.name, {
                -- via_curl_request = true,
                -- callback = function(response, err)
                --     if err then
                --         vim.notify("Failed to enable server: " .. err, vim.log.levels.ERROR)
                --     end
                -- end,
            })
        else
            State.hub_instance:stop_mcp_server(context.name, true, {
                -- via_curl_request = true,
                -- callback = function(response, err)
                --     if err then
                --         vim.notify("Failed to disable server: " .. err, vim.log.levels.ERROR)
                --     end
                -- end,
            })
        end
    elseif
        (type == "tool" or type == "resource" or type == "resourceTemplate" or type == "prompt")
        and context
        and State.hub_instance
    then
        local server_name = context.server_name
        local is_native = native.is_native_server(server_name)
        local server_config = (
            is_native and State.native_servers_config[server_name] or State.servers_config[server_name]
        ) or {}

        local type_config = {
            tool = { id_field = "name", config_field = "disabled_tools" },
            resource = { id_field = "uri", config_field = "disabled_resources" },
            resourceTemplate = { id_field = "uriTemplate", config_field = "disabled_resourceTemplates" },
            prompt = { id_field = "name", config_field = "disabled_prompts" },
        }

        local config = type_config[type]
        local capability_id = context.def[config.id_field]
        local disabled_list = vim.deepcopy(server_config[config.config_field] or {})
        local is_disabled = vim.tbl_contains(disabled_list, capability_id)

        -- Update disabled list based on desired state
        if is_disabled then
            for i, item_id in ipairs(disabled_list) do
                if item_id == capability_id then
                    table.remove(disabled_list, i)
                    break
                end
            end
        else
            table.insert(disabled_list, capability_id)
        end

        -- Update server config with new disabled list
        local updates = {}
        updates[config.config_field] = disabled_list
        State.hub_instance:update_server_config(server_name, updates)
        State:emit(type .. "_list_changed", {
            server_name = server_name,
            config_field = config.config_field,
            disabled_list = disabled_list,
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
function MainView:render_servers_section(title, servers, config_source, current_line, is_native)
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
        current_line = renderer.render_server_capabilities(server, lines, current_line, config_source, self, is_native)
    end

    return lines, current_line
end

--- Render all server sections
---@return NuiLine[]
function MainView:render_servers(line_offset)
    local lines = {}
    local current_line = line_offset

    local width = self:get_width() - (Text.HORIZONTAL_PADDING * 2)
    -- Start with top-level MCP Servers header
    local left_section = NuiLine():append("MCP Servers", Text.highlights.title)

    -- Add token count on MCP Servers section if connected
    if State:is_connected() and State.hub_instance and State.hub_instance:is_ready() then
        local prompts = State.hub_instance:generate_prompts()
        if prompts then
            -- Calculate total tokens from all prompts
            local active_servers_tokens = utils.calculate_tokens(prompts.active_servers or "")
            local use_mcp_tool_tokens = utils.calculate_tokens(prompts.use_mcp_tool or "")
            local access_mcp_resource_tokens = utils.calculate_tokens(prompts.access_mcp_resource or "")
            local total_tokens = active_servers_tokens + use_mcp_tool_tokens + access_mcp_resource_tokens

            if total_tokens > 0 then
                left_section:append(
                    " (~ " .. utils.format_token_count(total_tokens) .. " tokens)",
                    Text.highlights.muted
                )
            end
        end
    end
    local is_auto_approve_enabled = vim.g.mcphub_auto_approve == true
    local right_section = NuiLine()
        :append(Text.icons.auto, is_auto_approve_enabled and Text.highlights.success or Text.highlights.muted)
        :append(" Auto Approve: ", Text.highlights.muted)
        :append(
            is_auto_approve_enabled and "ON" or "OFF",
            is_auto_approve_enabled and Text.highlights.success or Text.highlights.muted
        )

    -- Calculate padding needed between sections
    local total_content_width = left_section:width() + right_section:width()
    local padding = width - total_content_width

    -- Combine sections with padding
    local header_line = NuiLine():append(left_section):append(string.rep(" ", padding)):append(right_section)

    table.insert(lines, Text.pad_line(header_line))
    current_line = current_line + 1
    -- Track breadcrumb line for interaction
    -- self:track_line(current_line, "breadcrumb", {
    --     hint = "<CR> to preview servers prompt",
    -- })
    table.insert(lines, self:divider())
    current_line = current_line + 1

    -- Render MCP servers section (without title since we already added it)
    local mcp_lines, new_line =
        self:render_servers_section(nil, State.server_state.servers, State.servers_config, current_line, false)
    vim.list_extend(lines, mcp_lines)
    current_line = new_line
    -- Add create server option
    -- table.insert(lines, Text.empty_line())
    table.insert(
        lines,
        Text.pad_line(
            NuiLine()
                :append(" " .. Text.icons.plus .. " ", Text.highlights.muted)
                :append("Add Server (A)", Text.highlights.muted)
        )
    )
    -- Track line for interaction
    self:track_line(current_line + 1, "add_server", {
        name = "Add Server",
        hint = "[<l> Open Editor]",
    })
    current_line = current_line + 1

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
        current_line,
        true
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
                :append("Auto-create Server", Text.highlights.muted)
        )
    )
    -- Track line for interaction
    self:track_line(current_line + 1, "create_server", {
        hint = "[<l> Create Server]",
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
        local cap_pos = self.cursor_positions.capability_line or self.active_capability:get_cursor_position()
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

function MainView:should_show_logs()
    return not vim.tbl_contains({ constants.HubState.READY, constants.HubState.RESTARTED }, State.server_state.state)
end

function MainView:render()
    -- Handle special states from base view
    if State.setup_state == "failed" or State.setup_state == "in_progress" then
        return View.render(self)
    end
    -- Get base header
    local lines = self:render_header(false)
    if self:should_show_logs() then
        local state_info = renderer.get_hub_info(State.server_state.state)
        local breadcrumb_line = NuiLine():append(state_info.icon, state_info.hl):append(state_info.desc, state_info.hl)
        table.insert(lines, Text.pad_line(breadcrumb_line))
        table.insert(lines, self:divider())
        vim.list_extend(lines, renderer.render_server_entries(State.server_output.entries, false))
        local errors = renderer.render_hub_errors(nil, false)
        if #errors > 0 then
            vim.list_extend(lines, errors)
        end
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
