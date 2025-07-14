---@brief [[
--- Config view for MCPHub UI
--- Shows MCP server configurations
---@brief ]]
local NuiLine = require("mcphub.utils.nuiline")
local Text = require("mcphub.utils.text")
local View = require("mcphub.ui.views.base")

---@class ConfigView:View
---@field current_tab_index number Currently selected tab index
---@field config_files string[] List of config file paths
local ConfigView = setmetatable({}, {
    __index = View,
})
ConfigView.__index = ConfigView

function ConfigView:new(ui)
    local instance = View:new(ui, "config") -- Create base view with name
    instance.current_tab_index = 1
    instance.config_files = {}
    return setmetatable(instance, ConfigView)
end

function ConfigView:before_enter()
    View.before_enter(self)

    -- Get active config files from ConfigManager
    local ConfigManager = require("mcphub.utils.config_manager")
    self.config_files = ConfigManager.get_active_config_files()

    -- Reverse the order of config files for tab display
    local reversed_files = {}
    for i = #self.config_files, 1, -1 do
        table.insert(reversed_files, self.config_files[i])
    end
    self.config_files = reversed_files

    -- Ensure we have a valid tab index
    if #self.config_files == 0 then
        self.current_tab_index = 1
    else
        self.current_tab_index = math.min(self.current_tab_index, #self.config_files)
    end

    -- Build keymaps based on available files
    self.keymaps = {
        ["e"] = {
            action = function()
                if #self.config_files > 0 then
                    local current_file = self.config_files[self.current_tab_index]
                    self.ui:toggle()
                    vim.cmd("edit " .. current_file)
                else
                    vim.notify("No configuration file available", vim.log.levels.ERROR)
                end
            end,
            desc = "Edit config",
        },
    }

    -- Add tab navigation keymaps only if multiple files exist
    if #self.config_files > 1 then
        self.keymaps["<Tab>"] = {
            action = function()
                self.current_tab_index = (self.current_tab_index % #self.config_files) + 1
                self:draw()
            end,
            desc = "Next tab",
        }
        -- self.keymaps["<S-Tab>"] = {
        --     action = function()
        --         self.current_tab_index = ((self.current_tab_index - 2) % #self.config_files) + 1
        --         self:draw()
        --     end,
        --     desc = "Previous tab",
        -- }
    end
end

function ConfigView:get_initial_cursor_position()
    -- Position at start of server configurations
    local lines = self:render_header()

    -- Add tab bar height if we have multiple files
    if #self.config_files > 0 then
        return #lines + 4 -- header + tab bar + separator
    else
        return #lines + 3 -- header + file info
    end
end

function ConfigView:render()
    -- Get base header
    local lines = self:render_header(false)

    if #self.config_files == 0 then
        -- No config files available
        table.insert(lines, Text.pad_line(NuiLine():append("No configuration files available", Text.highlights.warn)))
        return lines
    end

    -- Render tab bar if multiple files
    if #self.config_files > 0 then
        local tabs = {}
        for i, file_path in ipairs(self.config_files) do
            local file_name = vim.fn.fnamemodify(file_path, ":t") -- Get just filename
            local icon = Text.icons.folder -- Default to workspace/project icon

            -- Last file is treated as global
            if i == #self.config_files then
                icon = Text.icons.globe
            end

            table.insert(tabs, {
                text = icon .. " " .. file_name,
                selected = i == self.current_tab_index,
            })
        end

        table.insert(lines, Text.create_tab_bar(tabs, self:get_width()))
        table.insert(lines, Text.empty_line())
    end

    -- Show current file path
    local current_file = self.config_files[self.current_tab_index]
    if current_file then
        local file_line = NuiLine():append(Text.icons.file .. " " .. current_file, Text.highlights.muted)
        table.insert(lines, Text.pad_line(file_line))
    end

    table.insert(lines, Text.empty_line())

    -- Get and validate current file content
    local ConfigManager = require("mcphub.utils.config_manager")
    local file_content = ConfigManager.get_file_content_json(current_file)

    if not file_content then
        table.insert(lines, self:center(NuiLine():append("Failed to load configuration file", Text.highlights.error)))
        table.insert(lines, Text.empty_line())
    else
        -- Show file content with JSON highlighting
        vim.list_extend(lines, Text.render_json(file_content, { use_jq = true }))
    end

    return lines
end

return ConfigView
