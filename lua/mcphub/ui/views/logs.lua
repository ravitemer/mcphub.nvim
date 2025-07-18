---@brief [[
--- Logs view for MCPHub UI
--- Shows server output and errors
---@brief ]]
local State = require("mcphub.state")
local Text = require("mcphub.utils.text")
local View = require("mcphub.ui.views.base")
local renderer = require("mcphub.utils.renderer")

---@class LogsView:View
---@field active_tab "logs"|"issues" Currently active tab
local LogsView = setmetatable({}, {
    __index = View,
})
LogsView.__index = LogsView

function LogsView:new(ui)
    ---@class View
    local instance = View:new(ui, "logs") -- Create base view with name
    instance.active_tab = "logs"
    return setmetatable(instance, LogsView)
end

function LogsView:render_tabs()
    local tabs = {
        {
            text = "Server Logs",
            selected = self.active_tab == "logs",
        },
        {
            text = "Issues",
            selected = self.active_tab == "issues",
        },
    }
    return Text.create_tab_bar(tabs, self:get_width())
end

function LogsView:before_enter()
    View.before_enter(self)

    -- Set up keymaps
    self.keymaps = {
        ["<Tab>"] = {
            action = function()
                self.active_tab = self.active_tab == "logs" and "issues" or "logs"
                self:draw()
            end,
            desc = "Next tab",
        },
        ["<S-Tab>"] = {
            action = function()
                -- Since we only have 2 tabs, reverse is the same as forward
                self.active_tab = self.active_tab == "logs" and "issues" or "logs"
                self:draw()
            end,
            desc = "Previous tab",
        },
        ["x"] = {
            action = function()
                if self.active_tab == "logs" then
                    State.server_output.entries = {}
                else
                    State:clear_errors()
                end
                self:draw()
            end,
            desc = "Clear current tab",
        },
    }
end

function LogsView:render()
    -- Get base header
    local lines = self:render_header(false)

    -- Add tab bar
    table.insert(lines, self:render_tabs())
    -- table.insert(lines, self:divider())
    table.insert(lines, Text.empty_line())

    -- Show empty state placeholders when no content
    if self.active_tab == "logs" and #State.server_output.entries == 0 then
        table.insert(lines, Text.pad_line("No server logs yet", Text.highlights.muted))
    elseif self.active_tab == "issues" and #State.errors.items == 0 then
        table.insert(lines, Text.pad_line("No issues found - All systems running smoothly", Text.highlights.muted))
    else
        -- Render content based on active tab
        if self.active_tab == "logs" then
            -- Show server output entries
            vim.list_extend(lines, renderer.render_server_entries(State.server_output.entries))
        else
            -- Show all errors with details
            vim.list_extend(lines, renderer.render_hub_errors(nil, true))
        end
    end

    return lines
end

return LogsView
