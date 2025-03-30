---@brief [[
--- Help view for MCPHub UI
--- Shows plugin documentation and keybindings
---@brief ]]
local NuiLine = require("mcphub.utils.nuiline")
local Text = require("mcphub.utils.text")
local View = require("mcphub.ui.views.base")

---@class HelpView
---@field super View
---@field active_tab "readme"|"native"|"changelog" Currently active tab
local HelpView = setmetatable({}, {
    __index = View,
})
HelpView.__index = HelpView

function HelpView:new(ui)
    local self = View:new(ui, "help")
    self.active_tab = "readme"
    self = setmetatable(self, HelpView)
    return self
end

function HelpView:render_tabs()
    local tabs = {
        {
            text = "README",
            selected = self.active_tab == "readme",
        },
        {
            text = "Native Servers",
            selected = self.active_tab == "native",
        },
        {
            text = "Changelog",
            selected = self.active_tab == "changelog",
        },
    }
    return Text.create_tab_bar(tabs, self:get_width())
end

function HelpView:get_initial_cursor_position()
    -- Position after header
    local lines = self:render_header()
    return #lines + 2
end

function HelpView:before_enter()
    View.before_enter(self)

    -- Set up keymaps
    self.keymaps = {
        ["<Tab>"] = {
            action = function()
                if self.active_tab == "readme" then
                    self.active_tab = "native"
                elseif self.active_tab == "native" then
                    self.active_tab = "changelog"
                else
                    self.active_tab = "readme"
                end
                self:draw()
            end,
            desc = "Switch tab",
        },
    }
end

function HelpView:render()
    -- Get base header
    local lines = self:render_header(false)

    -- Add tab bar
    table.insert(lines, self:render_tabs())
    table.insert(lines, Text.empty_line())

    -- Get prompt utils for accessing documentation
    local prompt_utils = require("mcphub.utils.prompt")

    -- Render content based on active tab
    if self.active_tab == "readme" then
        local readme = prompt_utils.get_plugin_docs()
        if readme then
            vim.list_extend(lines, Text.render_markdown(readme))
        else
            table.insert(lines, Text.pad_line("README not found", Text.highlights.error))
        end
    elseif self.active_tab == "native" then
        -- Native server documentation
        local native_guide = prompt_utils.get_native_server_prompt()
        if native_guide then
            vim.list_extend(lines, Text.render_markdown(native_guide))
        else
            table.insert(lines, Text.pad_line("Native server guide not found", Text.highlights.error))
        end
    else -- changelog
        local changelog = prompt_utils.get_plugin_changelog()
        if changelog then
            vim.list_extend(lines, Text.render_markdown(changelog))
        else
            table.insert(lines, Text.pad_line("Changelog not found", Text.highlights.error))
        end
    end

    return lines
end

return HelpView
