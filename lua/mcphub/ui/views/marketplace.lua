---@brief [[
--- Marketplace view for MCPHub UI
--- Browse, search and install MCP servers
---@brief ]]
local Installers = require("mcphub.utils.installers")
local NuiLine = require("mcphub.utils.nuiline")
local State = require("mcphub.state")
local Text = require("mcphub.utils.text")
local View = require("mcphub.ui.views.base")

---@class MarketplaceView
---@field super View
---@field active_mode "browse"|"details" Current view mode
local MarketplaceView = setmetatable({}, {
    __index = View,
})
MarketplaceView.__index = MarketplaceView

function MarketplaceView:new(ui)
    local self = View:new(ui, "marketplace") -- Create base view with name
    self = setmetatable(self, MarketplaceView)

    -- Initialize state
    self.active_mode = "browse"
    self.selected_server = nil
    self.cursor_positions = {
        browse_mode = nil, -- Will store [line, col]
        details_mode = nil, -- Will store [line, col]
    }

    --  Setup initial keymaps (mode-specific keymaps set in setup_active_mode)
    self.keymaps = {}

    return self
end

-- Extract unique categories and tags from catalog items
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

-- Filter and sort catalog items
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
            return (a.createdAt or 0) > (b.createdAt or 0)
        end,
        downloads = function(a, b)
            return (a.downloadCount or 0) > (b.downloadCount or 0)
        end,
        stars = function(a, b)
            return (a.githubStars or 0) > (b.githubStars or 0)
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
end

function MarketplaceView:before_leave()
    -- Store current position based on mode
    if self.active_mode == "browse" then
        self.cursor_positions.browse_mode = vim.api.nvim_win_get_cursor(0)
    else
        self.cursor_positions.details_mode = vim.api.nvim_win_get_cursor(0)
    end
    View.before_leave(self)
end

function MarketplaceView:setup_active_mode()
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
                        { text = "Most Downloads", value = "downloads" },
                        { text = "Newest First", value = "newest" },
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
            ["<CR>"] = {
                action = function()
                    local cursor = vim.api.nvim_win_get_cursor(0)
                    local server = self:get_server_at_line(cursor[1])
                    if server then
                        -- Store browse mode position
                        self.cursor_positions.browse_mode = cursor
                        -- Switch to details mode
                        self.selected_server = server
                        self.active_mode = "details"
                        self:setup_active_mode()
                        -- Fetch details
                        if State.hub_instance then
                            State.hub_instance:get_marketplace_server_details(server.mcpId)
                        end
                        self:draw()
                        local install_line = self.interactive_lines[1]
                        vim.api.nvim_win_set_cursor(0, { install_line and install_line.line or 7, 0 })
                    end
                end,
                desc = "View details",
            },
        }
    else
        -- Details mode keymaps (simpler, focused on installation)
        self.keymaps = {
            ["<Esc>"] = {
                action = function()
                    -- Store details mode position
                    self.cursor_positions.details_mode = vim.api.nvim_win_get_cursor(0)
                    -- Switch back to browse mode
                    self.active_mode = "browse"
                    self.selected_server = nil
                    self:setup_active_mode()
                    self:draw()
                    -- Restore browse mode position
                    if self.cursor_positions.browse_mode then
                        vim.api.nvim_win_set_cursor(0, self.cursor_positions.browse_mode)
                    end
                end,
                desc = "Back to list",
            },
            ["<CR>"] = {
                action = function()
                    local cursor = vim.api.nvim_win_get_cursor(0)
                    local type, context = self:get_line_info(cursor[1])
                    -- Only allow installation if not already installed
                    if type == "install" and not State:is_server_installed(self.selected_server.mcpId) then
                        -- Get available installers
                        local available_installers = self:get_available_installers()

                        if #available_installers > 0 then
                            -- Create selection items with installer names
                            local items = vim.tbl_map(function(installer)
                                return installer.name
                            end, available_installers)

                            -- Show installer selection
                            vim.ui.select(items, {
                                prompt = "Choose installer:",
                            }, function(choice)
                                if choice then
                                    -- Find selected installer
                                    for _, installer in ipairs(available_installers) do
                                        if installer.name == choice then
                                            self:handle_install(self.selected_server, installer.id)
                                            break
                                        end
                                    end
                                end
                            end)
                        else
                            vim.notify(
                                "No installers available. Please install CodeCompanion or Avante.",
                                vim.log.levels.ERROR
                            )
                        end
                    end
                end,
                desc = "Install",
            },
        }
    end
    self:apply_keymaps()
end

-- Helper to find server at cursor line
function MarketplaceView:get_server_at_line(line)
    local type, context = self:get_line_info(line)
    if type == "server" and context.mcpId then
        -- Look up server in catalog by id
        for _, server in ipairs(State.marketplace_state.catalog.items) do
            if server.mcpId == context.mcpId then
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

function MarketplaceView:render_server_card(server, index, line_offset)
    local lines = {}
    local is_installed = State:is_server_installed(server.mcpId)

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

    -- Add recommended badge if server is recommended
    if server.isRecommended then
        meta_section:append(Text.icons.sparkles .. " ", Text.highlights.success)
    end

    -- Show stars and downloads
    meta_section
        :append(Text.icons.favorite, Text.highlights.muted)
        :append(" " .. (server.githubStars or "0"), Text.highlights.muted)
        :append(" ", Text.highlights.muted)
        :append(Text.icons.download, Text.highlights.muted)
        :append(" " .. (server.downloadCount or "0"), Text.highlights.muted)

    -- Calculate padding between name and metadata
    local padding = 2 -- width - (name_section:width() + meta_section:width())

    -- Combine name and metadata with padding
    local title_line = NuiLine():append(name_section):append(string.rep(" ", padding)):append(meta_section)

    -- Track line for server selection (storing only id)
    self:track_line(line_offset, "server", {
        type = "server",
        mcpId = server.mcpId,
        hint = "Press <CR> for details",
    })
    table.insert(lines, Text.pad_line(title_line))

    -- Description (with spacing)
    if server.description then
        -- table.insert(lines, Text.pad_line(NuiLine())) -- Add blank line before description
        table.insert(lines, Text.pad_line(NuiLine():append(server.description, Text.highlights.muted)))
    end

    table.insert(lines, Text.pad_line(NuiLine()))
    return lines
end

function MarketplaceView:render_browse_mode(line_offset)
    local lines = {}

    -- Show appropriate state
    local state = State.marketplace_state
    if state.status == "loading" then
        table.insert(lines, NuiLine())
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
            value = server.githubUrl,
            is_url = true,
        },
        {
            label = "Author   ",
            icon = Text.icons.octoface,
            value = server.author or "Unknown",
        },
        {
            label = "Downloads",
            icon = Text.icons.download,
            value = tostring(server.downloadCount or "0"),
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
    if server.mcpId then
        local details = State.marketplace_state.server_details[server.mcpId]
        local is_loading = details == nil
        local is_installed = State:is_server_installed(server.mcpId)

        -- Install button or status
        local button_line = NuiLine()
        if is_loading then
            -- Show only loading state
            button_line:append(" " .. Text.icons.loading .. " ", Text.highlights.muted)
            button_line:append("Loading...", Text.highlights.muted)
        elseif is_installed then
            -- Just show installed status
            button_line:append(" " .. Text.icons.install .. " ", Text.highlights.success)
            button_line:append("Installed", Text.highlights.success)
        else
            -- Show install button with available installers
            button_line:append(" " .. Text.icons.install .. " ", Text.highlights.active_item)
            button_line:append("Install", Text.highlights.active_item)
            button_line:append(" with: ", Text.highlights.muted)

            -- Check each installer
            for id, installer in pairs(Installers) do
                if installer.check() then
                    button_line
                        :append("[" .. installer.name .. "]", Text.highlights.success)
                        :append(" ", Text.highlights.muted)
                        :append(Text.icons.check, Text.highlights.success)
                        :append("  ", Text.highlights.muted)
                else
                    button_line
                        :append("[" .. installer.name .. "]", Text.highlights.error)
                        :append(" ", Text.highlights.muted)
                        :append(Text.icons.uninstall, Text.highlights.error)
                        :append("  ", Text.highlights.muted)
                end
            end
        end
        table.insert(lines, Text.pad_line(button_line))

        -- Only track install button if server is not installed and not loading
        if not is_loading and not is_installed then
            self:track_line(#lines + line_offset, "install", {
                type = "install",
                mcpId = server.mcpId,
                server = server,
                hint = "Press <CR> to install",
            })
        end
        table.insert(lines, Text.pad_line(NuiLine()))
        table.insert(lines, self:divider())
        table.insert(lines, Text.pad_line(NuiLine()))
    end

    -- Readme section
    local details = State.marketplace_state.server_details[server.mcpId]
    if details and details.data and type(details.data.readmeContent) == "string" then
        local readme = details.data.readmeContent
        if #readme > 0 then
            table.insert(
                lines,
                self:center(NuiLine():append(" " .. Text.icons.resource .. " README ", Text.highlights.header))
            )
            table.insert(lines, Text.pad_line(NuiLine()))
            vim.list_extend(lines, vim.tbl_map(Text.pad_line, Text.multiline(readme)))
            table.insert(lines, Text.pad_line(NuiLine()))
        end
    end

    return lines
end

function MarketplaceView:render()
    -- Handle special states from base view
    if State.setup_state == "failed" or State.setup_state == "in_progress" then
        return View.render(self)
    end
    -- Get base header
    local lines = self:render_header(false)

    -- Add title/breadcrumb
    if self.active_mode == "browse" then
        -- Render controls
        vim.list_extend(lines, self:render_header_controls())
    elseif self.selected_server then
        local is_installed = State:is_server_installed(self.selected_server.mcpId)
        local breadcrumb = NuiLine():append("Marketplace > ", Text.highlights.muted):append(
            self.selected_server.name,
            is_installed and Text.highlights.success or Text.highlights.title
        )
        if is_installed then
            breadcrumb:append(" ", Text.highlights.muted):append(Text.icons.install, Text.highlights.success)
        end
        if self.selected_server.githubStars and self.selected_server.githubStars > 0 then
            breadcrumb:append(
                " (" .. Text.icons.favorite .. " " .. tostring(self.selected_server.githubStars) .. ")",
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

function MarketplaceView:get_available_installers()
    local available = {}
    for id, installer in pairs(Installers) do
        if installer.check() then
            table.insert(available, {
                id = id,
                name = installer.name,
            })
        end
    end
    return available
end

function MarketplaceView:handle_install(server, installer_id)
    local installer = Installers[installer_id]
    if installer then
        self.ui:cleanup()
        installer.install(self, server)
    end
end

-- Helper to get server state from State
function MarketplaceView:get_server_state(mcpId)
    if State.server_state and State.server_state.servers then
        for _, server in ipairs(State.server_state.servers) do
            if server.name == mcpId then
                return server
            end
        end
    end
    return nil
end
return MarketplaceView
