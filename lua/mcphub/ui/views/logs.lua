---@brief [[
--- Logs view for MCPHub UI
--- Shows server output
---@brief ]]
local State = require("mcphub.state")
local View = require("mcphub.ui.views.base")
local Text = require("mcphub.utils.text")
local NuiLine = require("mcphub.utils.nuiline")
local renderer = require("mcphub.utils.renderer")

---@class LogsView
---@field super View
local LogsView = setmetatable({}, {
    __index = View
})
LogsView.__index = LogsView

function LogsView:new(ui)
    local self = View:new(ui, "logs") -- Create base view with name
    return setmetatable(self, LogsView)
end

function LogsView:before_enter()
    View.before_enter(self)

    -- Set up keymaps
    self.keymaps = {
        ["x"] = {
            action = function()
                State.server_output.entries = {}
                self:draw()
            end,
            desc = "Clear logs"
        }
    }
end

-- Render server output section
function LogsView:render_server_output()
    local lines = {}
    table.insert(lines, Text.pad_line(" MCP Hub Logs ", Text.highlights.header))
    table.insert(lines, Text.pad_line(""))
    vim.list_extend(lines, renderer.render_server_entries(State.server_output.entries))
    return lines
end

function LogsView:render()
    -- Get base header
    local lines = self:render_header()

    -- Add server output
    vim.list_extend(lines, self:render_server_output())

    return lines
end

return LogsView
