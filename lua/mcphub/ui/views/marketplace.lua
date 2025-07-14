---[[
--- Marketplace view for MCPHub UI
--- Browse, search and install MCP servers
---]]
local NuiLine = require("mcphub.utils.nuiline")
local State = require("mcphub.state")
local Text = require("mcphub.utils.text")
local View = require("mcphub.ui.views.base")
local utils = require("mcphub.utils")

---@class MarketplaceView: View
---@field active_mode "browse"|"details" Current view mode
---@field selected_server MarketplaceItem|nil Currently selected server
---@field cursor_positions table
---@field active_installation_index number Currently selected installation method index
local MarketplaceView = setmetatable({}, {
    __index = View,
})
MarketplaceView.__index = MarketplaceView

function MarketplaceView:new(ui)
    local instance = View:new(ui, "marketplace") -- Create base view with name
    instance = setmetatable(instance, MarketplaceView)

    -- Initialize state
    instance.active_mode = "browse"
    instance.selected_server = nil
    instance.cursor_positions = {
        browse_mode = nil, -- Will store [line, col]
        details_mode = nil, -- Will store [line, col]
    }
    --  Setup initial keymaps (mode-specific keymaps set in setup_active_mode)
    instance.keymaps = {}

    return instance
end

---Extract unique categories and tags from catalog items
---@return string[]
function MarketplaceView:get_available_categories()
    local categories = {}
    local seen = {}

    -- Get items from state
    local items = State.marketplace_state.catalog.items or {}

    for _, item in ipairs(items) do
        -- Add main category
        if item.category and not seen[item.category] then
            seen[item.category] = true
            table.insert(categories, item.category)
        end

        -- Add tags
        if item.tags then
            for _, tag in ipairs(item.tags) do
                if not seen[tag] then
                    seen[tag] = true
                    table.insert(categories, tag)
                end
            end
        end
    end

    -- Sort categories alphabetically
    table.sort(categories)

    return categories
end

--- Filter and sort catalog items
---@param items MarketplaceItem[] List of items to filter and sort
---@return MarketplaceItem[] Filtered and sorted items
function MarketplaceView:filter_and_sort_items(items)
    if not items or #items == 0 then
        return {}
    end

    local filters = State.marketplace_state.filters
    local filtered = items

    -- Apply search filter with ranking
    if filters.search ~= "" and #filters.search > 0 then
        local ranked_items = {}
        local search_text = filters.search:lower()

        -- First pass: collect items with ranks
        for _, item in ipairs(filtered) do
            local rank = 5 -- Default rank (no match)

            if item.name then
                local name_lower = item.name:lower()
                if name_lower == search_text then
                    rank = 1 -- Exact name match
                elseif name_lower:find("^" .. search_text) then
                    rank = 2 -- Name starts with search text
                elseif name_lower:find(search_text) then
                    rank = 3 -- Name contains search text
                end
            end

            -- Check description only if we haven't found a name match
            if rank == 5 and item.description and item.description:lower():find(search_text) then
                rank = 4 -- Description match
            end

            -- Only include items that actually matched
            if rank < 5 then
                table.insert(ranked_items, {
                    item = item,
                    rank = rank,
                })
            end
        end

        -- Sort by rank
        table.sort(ranked_items, function(a, b)
            if a.rank ~= b.rank then
                return a.rank < b.rank
            end
            -- If ranks are equal, sort by name
            return (a.item.name or ""):lower() < (b.item.name or ""):lower()
        end)

        -- Extract just the items
        filtered = vim.tbl_map(function(ranked)
            return ranked.item
        end, ranked_items)
        return filtered
    end

    -- Apply category filter
    if filters.category ~= "" then
        filtered = vim.tbl_filter(function(item)
            -- Match against main category or tags
            return (item.category == filters.category) or (item.tags and vim.tbl_contains(item.tags, filters.category))
        end, filtered)
    end

    -- Sort results
    local sort_funcs = {
        newest = function(a, b)
            return (a.lastCommit or 0) > (b.lastCommit or 0)
        end,
        downloads = function(a, b)
            return #(a.installations or {}) > #(b.installations or {})
        end,
        stars = function(a, b)
            return (a.stars or 0) > (b.stars or 0)
        end,
        name = function(a, b)
            return (a.name or ""):lower() < (b.name or ""):lower()
        end,
    }

    if filters.sort and sort_funcs[filters.sort] then
        table.sort(filtered, sort_funcs[filters.sort])
    end

    return filtered
end

function MarketplaceView:before_enter()
    View.before_enter(self)
    self:setup_active_mode()
end

-- Add this to the MarketplaceView:after_enter() function
function MarketplaceView:after_enter()
    View.after_enter(self)

    -- Restore appropriate cursor position for current mode
    local line_count = vim.api.nvim_buf_line_count(self.ui.buffer)
    if self.active_mode == "browse" and self.cursor_positions.browse_mode then
        local new_pos = {
            math.min(self.cursor_positions.browse_mode[1], line_count),
            self.cursor_positions.browse_mode[2],
        }
        vim.api.nvim_win_set_cursor(0, new_pos)
    elseif self.active_mode == "details" then
        local install_line = self.interactive_lines[1]
        vim.api.nvim_win_set_cursor(0, { install_line and install_line.line or 7, 0 })
    end

    local group = vim.api.nvim_create_augroup("MarketplaceView", { clear = true })
    -- Set up autocmd for visual selection in details mode
    if self.active_mode == "details" then
        -- Clear any existing autocmds for this buffer
        vim.api.nvim_clear_autocmds({
            buffer = self.ui.buffer,
            group = group,
        })
    end
end

function MarketplaceView:before_leave()
    -- Store current position based on mode
    if self.active_mode == "browse" then
        self.cursor_positions.browse_mode = vim.api.nvim_win_get_cursor(0)
    else
        self.cursor_positions.details_mode = vim.api.nvim_win_get_cursor(0)
    end
    -- Clear visual mode keymap if it was set
    if self._visual_keymap_set then
        pcall(vim.api.nvim_buf_del_keymap, self.ui.buffer, "v", "a")
        self._visual_keymap_set = false
    end

    View.before_leave(self)
end

function MarketplaceView:setup_active_mode()
    local function enter_detail_mode()
        local cursor = vim.api.nvim_win_get_cursor(0)
        local server = self:get_server_at_line(cursor[1])
        if server then
            self.cursor_positions.browse_mode = cursor
            self.selected_server = server
            self.active_mode = "details"
            self.active_installation_index = 1
            self:setup_active_mode()
            self:draw()
            local install_line = self.interactive_lines[1]
            vim.api.nvim_win_set_cursor(0, { install_line and install_line.line or 7, 0 })
        end
    end
    local function go_to_browse_mode()
        self.cursor_positions.details_mode = vim.api.nvim_win_get_cursor(0)
        self.active_mode = "browse"
        self.selected_server = nil
        self:setup_active_mode()
        self:draw()
        -- Restore browse mode position
        if self.cursor_positions.browse_mode then
            vim.api.nvim_win_set_cursor(0, self.cursor_positions.browse_mode)
        end
    end
    local function install_server()
        local cursor = vim.api.nvim_win_get_cursor(0)
        local type, context = self:get_line_info(cursor[1])

        if type == "install_with_method" and not State:is_server_installed(self.selected_server.id) then
            -- Open installation editor directly
            self:handle_installation_selection(
                context --[[@as { server: MarketplaceItem, installation: MarketplaceInstallation }]]
            )
        elseif type == "uninstall_server" and State:is_server_installed(self.selected_server.id) then
            -- Show confirmation and uninstall
            if context then
                local server_id = context.server.id --[[@as string]]
                utils.confirm_and_delete_server(server_id)
            end
        end
    end
    local function cycle_method(forward)
        if self.selected_server and self.selected_server.installations then
            local num_installations = #self.selected_server.installations
            if num_installations >= 1 then
                local is_installed = State:is_server_installed(self.selected_server.id)
                local max_index = is_installed and num_installations + 1 or num_installations

                if forward then
                    self.active_installation_index = (self.active_installation_index % max_index) + 1
                else
                    self.active_installation_index = ((self.active_installation_index - 2) % max_index) + 1
                end

                self:draw()
                -- Keep cursor on install/uninstall line
                if self.interactive_lines and #self.interactive_lines > 0 then
                    for _, line_info in ipairs(self.interactive_lines) do
                        if line_info.type == "install_with_method" or line_info.type == "uninstall_server" then
                            vim.api.nvim_win_set_cursor(0, { line_info.line, 0 })
                            break
                        end
                    end
                end
            end
        end
    end
    if self.active_mode == "browse" then
        self.keymaps = {
            ["/"] = {
                action = function()
                    vim.ui.input({
                        prompt = "Search: ",
                    }, function(input)
                        local trimmed = input and vim.trim(input)
                        if trimmed and #trimmed > 0 then -- Only update if input has content
                            -- When searching, clear category filter
                            local current = State.marketplace_state.filters or {}
                            State:update({
                                marketplace_state = {
                                    filters = {
                                        search = input,
                                        category = "", -- Clear category when searching
                                        sort = current.sort, -- Preserve sort
                                    },
                                },
                            }, "marketplace")
                            self:focus_first_interactive_line()
                        end
                    end)
                end,
                desc = "Search",
            },
            ["s"] = {
                action = function()
                    local sorts = {
                        { text = "Most Stars", value = "stars" },
                        -- { text = "Most Installations", value = "downloads" },
                        { text = "Recently Updated", value = "newest" },
                        { text = "Name (A-Z)", value = "name" },
                    }
                    vim.ui.select(sorts, {
                        prompt = "Sort by:",
                        format_item = function(item)
                            return item.text
                        end,
                    }, function(choice)
                        if choice then
                            State:update({
                                marketplace_state = {
                                    filters = {
                                        sort = choice.value,
                                    },
                                },
                            }, "marketplace")
                        end
                    end)
                end,
                desc = "Sort",
            },
            ["c"] = {
                action = function()
                    local categories = self:get_available_categories()
                    table.insert(categories, 1, "All Categories")

                    vim.ui.select(categories, {
                        prompt = "Filter by category:",
                    }, function(choice)
                        if choice then
                            -- When selecting category, clear search filter
                            local current = State.marketplace_state.filters or {}
                            State:update({
                                marketplace_state = {
                                    filters = {
                                        category = choice ~= "All Categories" and choice or "",
                                        search = "", -- Clear search when filtering by category
                                        sort = current.sort, -- Preserve sort
                                    },
                                },
                            }, "marketplace")
                            self:focus_first_interactive_line()
                        end
                    end)
                end,
                desc = "Category",
            },
            ["<Esc>"] = {
                action = function()
                    -- Only clear filters if any are active
                    local current = State.marketplace_state.filters or {}
                    if current.category or #(current.search or "") > 0 then
                        State:update({
                            marketplace_state = {
                                filters = {
                                    sort = current.sort, -- Preserve sort
                                    search = "",
                                    category = "",
                                },
                            },
                        }, "marketplace")
                    end
                end,
                desc = "Clear filters",
            },
            ["l"] = {
                action = enter_detail_mode,
                desc = "View details",
            },
            ["<Cr>"] = {
                action = enter_detail_mode,
                desc = "View details",
            },
        }
    else
        self.keymaps = {
            ["<Esc>"] = {
                action = go_to_browse_mode,
                desc = "Back to list",
            },
            ["l"] = {
                action = function()
                    cycle_method(true)
                end,
                desc = "Switch method",
            },
            ["h"] = {
                action = function()
                    cycle_method(false)
                end,
                desc = "Switch method",
            },
            ["<Cr>"] = {
                action = install_server,
                desc = "Install/Uninstall",
            },
        }
    end
    self:apply_keymaps()
end

--- Handle installation selection from details mode
---@param context { server: MarketplaceItem, installation: MarketplaceInstallation }
function MarketplaceView:handle_installation_selection(context)
    local server = context.server
    local installation = context.installation

    -- Create server config object with the server ID
    local server_config = {
        [server.id] = vim.json.decode(installation.config),
    }

    -- Open the editor with the pre-populated config
    utils.open_server_editor({
        title = "Install " .. server.name .. " (" .. installation.name .. ")",
        placeholder = utils.pretty_json(vim.json.encode(server_config)),
        start_insert = false,
        go_to_placeholder = true, -- Position cursor at first ${} placeholder
        virtual_lines = {
            {
                Text.icons.hint .. " ${VARIABLES} will be resolved from environment if not replaced",
                Text.highlights.muted,
            },
            { Text.icons.hint .. " ${cmd: echo 'secret'} will run command and replace ${}", Text.highlights.muted },
        },
        on_success = function()
            -- Switch to main view and browse mode after successful installation
            self.active_mode = "browse"
            self.selected_server = nil
            self.active_installation_index = nil
            self.ui:switch_view("main")
        end,
    })
end

--- Render installation details for a server
---@param installation MarketplaceInstallation
---@param line_offset number
function MarketplaceView:render_installation_details(installation, line_offset)
    local lines = {}

    -- Configuration preview (no indent)
    if installation.config then
        vim.list_extend(lines, Text.render_json(installation.config))
        table.insert(lines, Text.pad_line(NuiLine()))
    end

    -- Placeholders section (only show if parameters exist)
    if installation.parameters and #installation.parameters > 0 then
        table.insert(lines, Text.pad_line(NuiLine():append("Placeholders", Text.highlights.muted)))

        for _, param in ipairs(installation.parameters) do
            -- Single line: key: placeholder
            local placeholder_line = NuiLine()
            if param.required ~= false then
                placeholder_line:append("* ", Text.highlights.error)
            else
                placeholder_line:append("  ", Text.highlights.error)
            end
            placeholder_line:append(param.key, Text.highlights.json_property)
            placeholder_line:append(": ", Text.highlights.json_punctuation)
            if param.placeholder then
                placeholder_line:append(param.placeholder, Text.highlights.muted)
            end
            table.insert(lines, Text.pad_line(placeholder_line))
        end

        table.insert(lines, Text.pad_line(NuiLine()))
    end

    return lines
end

--- Render current server configuration in details mode
---@param server MarketplaceItem
---@param line_offset number
function MarketplaceView:render_current_server_config(server, line_offset)
    local lines = {}

    -- Get current server configuration
    local current_config = nil
    if State.hub_instance then
        -- Load the current config from servers.json
        local config_result = State.hub_instance:load_config()
        if config_result and config_result.mcpServers and config_result.mcpServers[server.id] then
            current_config = config_result.mcpServers[server.id]
        end
    end

    if current_config then
        -- Render current config as JSON
        vim.list_extend(lines, Text.render_json(vim.json.encode(current_config)))
        table.insert(lines, Text.pad_line(NuiLine()))
    else
        table.insert(lines, Text.pad_line(NuiLine():append("Current configuration not found", Text.highlights.warn)))
        table.insert(lines, Text.pad_line(NuiLine()))
    end

    return lines
end

--- Helper to find server at cursor line
--- @param line number Line number to check
---@return MarketplaceItem|nil
function MarketplaceView:get_server_at_line(line)
    local type, context = self:get_line_info(line)
    if type == "server" and (context and context.id) then
        -- Look up server in catalog by id
        for _, server in ipairs(State.marketplace_state.catalog.items) do
            if server.id == context.id then
                return server
            end
        end
    end
    return nil
end

function MarketplaceView:render_header_controls()
    local lines = {}
    local width = self:get_width() - (Text.HORIZONTAL_PADDING * 2)
    local filters = State.marketplace_state.filters

    -- Create status sections showing current filters and controls
    local left_section = NuiLine()
        :append(Text.icons.sort .. " ", Text.highlights.muted)
        :append("(", Text.highlights.muted)
        :append("s", Text.highlights.keymap)
        :append(")", Text.highlights.muted)
        :append("ort: ", Text.highlights.muted)
        :append(filters.sort == "" and "stars" or filters.sort, Text.highlights.info)
        :append("  ", Text.highlights.muted)
        :append(Text.icons.tag .. " ", Text.highlights.muted)
        :append("(", Text.highlights.muted)
        :append("c", Text.highlights.keymap)
        :append(")", Text.highlights.muted)
        :append("ategory: ", Text.highlights.muted)
        :append(filters.category == "" and "All" or filters.category, Text.highlights.info)

    -- Show filter clear hint if any filters active
    local has_filters = filters.category ~= "" or #(filters.search or "") > 0
    if has_filters then
        left_section
            :append(" (", Text.highlights.muted)
            :append("<Esc>", Text.highlights.keymap)
            :append(" to clear)", Text.highlights.muted)
    end

    local right_section =
        NuiLine():append("/", Text.highlights.keymap):append(" Search: ", Text.highlights.muted):append(
            filters.search == "" and "" or filters.search,
            #(filters.search or "") > 0 and Text.highlights.info or Text.highlights.muted
        )

    -- Calculate padding needed between sections
    local total_content_width = left_section:width() + right_section:width()
    local padding = width - total_content_width

    -- Combine sections with padding
    local controls_line = NuiLine():append(left_section):append(string.rep(" ", padding)):append(right_section)

    table.insert(lines, Text.pad_line(controls_line))

    return lines
end

--- Render a server card for the marketplace
---@param server MarketplaceItem
---@param index number
---@param line_offset number
function MarketplaceView:render_server_card(server, index, line_offset)
    local lines = {}
    local is_installed = State:is_server_installed(server.id)

    -- Create server name section (left part)
    local name_section = NuiLine():append(
        tostring(index) .. ") " .. server.name,
        is_installed and Text.highlights.success or Text.highlights.title
    )

    -- Show checkmark if installed
    if is_installed then
        name_section:append(" ", Text.highlights.muted):append(Text.icons.install, Text.highlights.success)
    end

    -- Create metadata section (right part)
    local meta_section = NuiLine()

    -- Add featured badge if server is featured
    if server.featured then
        meta_section:append(Text.icons.sparkles .. " ", Text.highlights.success)
    end

    -- Show stars and installations count
    meta_section
        :append(Text.icons.favorite, Text.highlights.muted)
        :append(" " .. (server.stars or "0"), Text.highlights.muted)
        :append(" ", Text.highlights.muted)

    -- Calculate padding between name and metadata
    local padding = 2 -- width - (name_section:width() + meta_section:width())

    -- Combine name and metadata with padding
    local title_line = NuiLine():append(name_section):append(string.rep(" ", padding)):append(meta_section)

    -- Track line for server selection (storing only id)
    self:track_line(line_offset, "server", {
        type = "server",
        id = server.id,
        hint = "[<l> Details]",
    })
    table.insert(lines, Text.pad_line(title_line))

    if server.description then
        table.insert(lines, Text.pad_line(NuiLine():append(server.description, Text.highlights.muted)))
    end

    table.insert(lines, Text.pad_line(NuiLine()))
    return lines
end

--- Render marketplace in browse mode
--- @param line_offset number Offset to apply to line numbers for tracking
function MarketplaceView:render_browse_mode(line_offset)
    local lines = {}

    -- Show appropriate state
    local state = State.marketplace_state
    if state.status == "loading" or state.status == "empty" then
        table.insert(lines, Text.pad_line(NuiLine():append("Loading marketplace catalog...", Text.highlights.muted)))
    elseif state.status == "error" then
        table.insert(
            lines,
            Text.pad_line(
                NuiLine()
                    :append(Text.icons.error .. " ", Text.highlights.error)
                    :append("Failed to load marketplace", Text.highlights.error)
            )
        )
    else
        -- Get filtered and sorted items
        local all_items = state.catalog.items or {}
        local filtered_items = self:filter_and_sort_items(all_items)

        -- Show result count if filters are active
        if #(state.filters.search or "") > 0 or state.filters.category ~= "" then
            local count_line = NuiLine()
                :append("Found ", Text.highlights.muted)
                :append(tostring(#filtered_items), Text.highlights.info)
                :append(" of ", Text.highlights.muted)
                :append(tostring(#all_items), Text.highlights.muted)
                :append(" servers", Text.highlights.muted)
            table.insert(lines, Text.pad_line(count_line))
            table.insert(lines, Text.empty_line())
        end

        -- Show filtered catalog
        if #filtered_items == 0 then
            if #all_items == 0 then
                table.insert(
                    lines,
                    Text.pad_line(NuiLine():append("No servers found in marketplace", Text.highlights.muted))
                )
            else
                table.insert(lines, Text.pad_line(NuiLine():append("No matching servers found", Text.highlights.muted)))
            end
        else
            for i, server in ipairs(filtered_items) do
                vim.list_extend(lines, self:render_server_card(server, i, #lines + line_offset + 1))
            end
        end
    end

    local info_line = NuiLine()
    info_line:append(Text.icons.bug .. " Report issues or suggest changes: ", Text.highlights.title)
    info_line:append("https://github.com/ravitemer/mcp-registry", Text.highlights.link)
    table.insert(lines, Text.pad_line(info_line))
    return lines
end

function MarketplaceView:render_details_mode(line_offset)
    local lines = {}
    local server = self.selected_server
    if not server then
        return lines
    end

    -- Description
    if server.description then
        vim.list_extend(lines, vim.tbl_map(Text.pad_line, Text.multiline(server.description, Text.highlights.muted)))
    end

    table.insert(lines, Text.empty_line())

    -- Server info section
    local info_lines = {
        {
            label = "URL      ",
            icon = Text.icons.link,
            value = server.url,
            is_url = true,
        },
        {
            label = "ID       ",
            icon = Text.icons.info,
            value = server.id,
        },
        {
            label = "Author   ",
            icon = Text.icons.octoface,
            value = server.author or "Unknown",
        },
    }

    -- Add category and tags together
    if server.category then
        local category_value = server.category
        if type(server.tags) == "table" and #server.tags > 0 then
            category_value = category_value .. " [" .. table.concat(server.tags, ", ") .. "]"
        end
        table.insert(info_lines, {
            label = "Tags     ",
            icon = Text.icons.tag,
            value = server.category,
            suffix = type(server.tags) == "table"
                    and #server.tags > 0
                    and (" [" .. table.concat(server.tags, ", ") .. "]")
                or nil,
        })
    end

    -- Render info lines
    for _, info in ipairs(info_lines) do
        if info.value then
            local line = NuiLine()
                :append(info.icon .. "  ", Text.highlights.title)
                :append(info.label .. " : ", Text.highlights.muted)
                :append(info.value, info.is_url and Text.highlights.link or info.highlight or Text.highlights.info)

            if info.suffix then
                line:append(info.suffix, Text.highlights.muted)
            end

            table.insert(lines, Text.pad_line(line))
        end
    end
    table.insert(lines, Text.pad_line(NuiLine()))

    -- Install section
    if server.id then
        local is_installed = State:is_server_installed(server.id)

        if is_installed then
            -- Create uninstall button with Current as first tab
            local uninstall_line = NuiLine()
            uninstall_line:append(Text.icons.uninstall .. " Uninstall: ", Text.highlights.error)

            -- Add Current as index 0 (special case)
            uninstall_line:append(" ")
            local current_active = self.active_installation_index == 1
            local current_highlight = current_active and Text.highlights.button_active
                or Text.highlights.button_inactive
            uninstall_line:append(" Current Config ", current_highlight)

            if #server.installations > 0 then
                uninstall_line:append(" " .. Text.icons.vertical_bar, Text.highlights.muted)
                uninstall_line:append(" Available: ", Text.highlights.muted)
            end
            -- Add installation method tabs
            for i, installation in ipairs(server.installations) do
                uninstall_line:append(" ")

                local is_active = self.active_installation_index == (i + 1)
                local tab_highlight = is_active and Text.highlights.button_active or Text.highlights.button_inactive

                uninstall_line:append(" " .. installation.name .. " ", tab_highlight)
            end
            table.insert(lines, Text.pad_line(uninstall_line))

            -- Track the uninstall line for interaction
            self:track_line(#lines + line_offset, "uninstall_server", {
                type = "uninstall_server",
                server = server,
                hint = "[<Cr> Uninstall, <l> Switch Method]",
            })

            table.insert(lines, Text.pad_line(NuiLine()))
            -- local prereq_line = NuiLine()
            -- prereq_line:append("PREVIEW ", Text.highlights.muted)
            -- table.insert(lines, Text.pad_line(prereq_line))
            table.insert(lines, self:divider())

            -- Show details based on active tab
            if self.active_installation_index == 1 then
                -- Show current server configuration when Current tab is active
                vim.list_extend(lines, self:render_current_server_config(server, line_offset))
            else
                -- Show installation details when an installation method is active
                local active_installation = server.installations[self.active_installation_index - 1]
                if active_installation then
                    vim.list_extend(lines, self:render_installation_details(active_installation, line_offset))
                end
            end
        else
            -- Show installation interface
            if server.installations and #server.installations > 0 then
                local active_installation = server.installations[self.active_installation_index]

                -- Create install button with method tabs
                local install_line = NuiLine()
                install_line:append(Text.icons.install .. " Install ", Text.highlights.success)
                install_line:append("using: ", Text.highlights.muted)

                -- Add installation method tabs
                for i, installation in ipairs(server.installations) do
                    if i > 1 then
                        install_line:append(" ")
                    end

                    local is_active = i == self.active_installation_index
                    local tab_highlight = is_active and Text.highlights.button_active or Text.highlights.button_inactive

                    install_line:append(" " .. installation.name .. " ", tab_highlight)
                end

                table.insert(lines, Text.pad_line(install_line))

                -- Track the install line for interaction
                self:track_line(#lines + line_offset, "install_with_method", {
                    type = "install_with_method",
                    server = server,
                    installation = active_installation,
                    hint = "[<Cr> Install, <l> Switch Method]",
                })

                table.insert(lines, Text.pad_line(NuiLine()))

                -- Show prerequisites before divider (single line)
                -- if active_installation.prerequisites and #active_installation.prerequisites > 0 then
                --     local prereq_line = NuiLine()
                --     prereq_line:append("Requires: ", Text.highlights.muted)
                --     prereq_line:append(table.concat(active_installation.prerequisites, ", "), Text.highlights.warn)
                --     table.insert(lines, Text.pad_line(prereq_line))
                -- end

                -- local prereq_line = NuiLine()
                -- prereq_line:append("PREVIEW ", Text.highlights.muted)
                -- table.insert(lines, Text.pad_line(prereq_line))
                table.insert(lines, self:divider())

                -- Show active installation details
                vim.list_extend(lines, self:render_installation_details(active_installation, line_offset))
            else
                table.insert(
                    lines,
                    Text.pad_line(NuiLine():append("No installation methods available", Text.highlights.warn))
                )
            end
        end
    end

    -- Show info links
    local info_line = NuiLine()
    info_line:append("For more information, visit: ", Text.highlights.muted)
    info_line:append(server.url, Text.highlights.muted)
    table.insert(lines, Text.pad_line(info_line))

    local bug_line = NuiLine()
    bug_line:append("Report issues or suggest changes: ", Text.highlights.muted)
    bug_line:append("https://github.com/ravitemer/mcp-registry", Text.highlights.muted)
    table.insert(lines, Text.pad_line(bug_line))
    return lines
end

function MarketplaceView:render()
    -- Handle special states from base view
    if State.setup_state == "failed" or State.setup_state == "in_progress" or State.setup_state == "not_started" then
        return View.render(self)
    end
    -- Get base header
    local lines = self:render_header(false)

    -- Add title/breadcrumb
    if self.active_mode == "browse" then
        -- Render controls
        vim.list_extend(lines, self:render_header_controls())
    elseif self.selected_server then
        local is_installed = State:is_server_installed(self.selected_server.id)
        local breadcrumb = NuiLine():append("Marketplace > ", Text.highlights.muted):append(
            self.selected_server.name,
            is_installed and Text.highlights.success or Text.highlights.title
        )
        if is_installed then
            breadcrumb:append(" ", Text.highlights.muted):append(Text.icons.install, Text.highlights.success)
        end
        if self.selected_server.stars and self.selected_server.stars > 0 then
            breadcrumb:append(
                " (" .. Text.icons.favorite .. " " .. tostring(self.selected_server.stars) .. ")",
                Text.highlights.muted
            )
        end
        table.insert(lines, Text.pad_line(breadcrumb))
    else
        -- Fallback if server not loaded yet
        local breadcrumb = NuiLine():append("Marketplace", Text.highlights.title)
        table.insert(lines, Text.pad_line(breadcrumb))
    end
    table.insert(lines, self:divider())

    -- Calculate line offset from header
    local line_offset = #lines

    -- Render current mode with line offset
    if self.active_mode == "browse" then
        vim.list_extend(lines, self:render_browse_mode(line_offset))
    else
        vim.list_extend(lines, self:render_details_mode(line_offset))
    end

    return lines
end

-- Get available installers
function MarketplaceView:focus_first_interactive_line()
    vim.schedule(function()
        if self.interactive_lines and #self.interactive_lines > 0 then
            vim.api.nvim_win_set_cursor(0, { self.interactive_lines[1].line, 0 })
        end
    end)
end

return MarketplaceView
