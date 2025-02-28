---@brief [[
--- Main dashboard view for MCPHub
--- Shows server status and connected servers
---@brief ]]
local State = require("mcphub.state")
local View = require("mcphub.ui.views.base")
local Text = require("mcphub.utils.text")
local NuiLine = require("mcphub.utils.nuiline")
local renderer = require("mcphub.utils.renderer")

---@class MainView
---@field super View
local MainView = setmetatable({}, {
    __index = View
})
MainView.__index = MainView

function MainView:new(ui)
    local self = View:new(ui, "main") -- Create base view with name
    return setmetatable(self, MainView)
end

--- Render server status section
---@param width number Window width
---@return NuiLine[]
function MainView:render_server_status(width)
    local lines = {}

    -- Server state header and status
    local status_text = ({
        connected = "Connected",
        connecting = "Connecting...",
        disconnected = "Disconnected"
    })[State.server_state.status] or "Unknown"

    local status_hl = ({
        connected = Text.highlights.success,
        connecting = Text.highlights.info,
        disconnected = Text.highlights.warning
    })[State.server_state.status] or Text.highlights.error

    -- Status line with icon
    local status_icon = ({
        connected = "● ",
        connecting = "◉ ",
        disconnected = "○ "
    })[State.server_state.status] or "⚠ "

    local status_line = NuiLine():append(status_icon, status_hl):append(status_text, status_hl)

    table.insert(lines, Text.pad_line(status_line))

    if State.server_state.status == "connected" then
        if State.server_state.started_at then
            local utils = require("mcphub.utils")
            local time_line = NuiLine():append("Started ", Text.highlights.muted):append(utils.format_relative_time(
                State.server_state.started_at))
            table.insert(lines, Text.pad_line(time_line))
        end
    else
        vim.list_extend(lines, renderer.render_server_entries(State.server_output.entries, false))
    end
    table.insert(lines, Text.empty_line())
    return lines
end

--- Render connected servers section
---@return NuiLine[]
function MainView:render_servers()
    local lines = {}

    if not State.server_state.servers or #State.server_state.servers == 0 then
        -- No servers connected
        table.insert(lines, Text.pad_line(NuiLine():append("No servers connected", Text.highlights.muted)))
        table.insert(lines, Text.empty_line())
        return lines
    end

    -- Section header
    table.insert(lines, Text.section("Connected Servers", {}, true)[1])

    -- Show each server
    for _, server in ipairs(State.server_state.servers) do
        -- Server name and status
        local server_line = NuiLine():append("• ", Text.highlights.muted):append(server.name .. " ",
            Text.highlights.success):append("(" .. server.status .. ")", Text.highlights.info)
        table.insert(lines, Text.pad_line(server_line))

        -- Server capabilities
        if server.capabilities then
            local cap_line = NuiLine():append("  └─ ", Text.highlights.muted):append("Tools: ",
                Text.highlights.muted):append(tostring(#server.capabilities.tools), Text.highlights.info):append(", ",
                Text.highlights.muted):append("Resources: ", Text.highlights.muted):append(
                tostring(#server.capabilities.resources), Text.highlights.info)
            table.insert(lines, Text.pad_line(cap_line))
        end
    end

    table.insert(lines, Text.empty_line())
    return lines
end

function MainView:render()
    -- Handle special states from base view
    if State.setup_state == "failed" or State.setup_state == "in_progress" then
        return View.render(self)
    end

    -- Get base header
    local lines = self:render_header()
    local width = self:get_width()

    -- Server status section
    vim.list_extend(lines, self:render_server_status(width))

    -- Connected servers section
    vim.list_extend(lines, self:render_servers())

    -- Recent errors section
    vim.list_extend(lines, renderer.render_hub_errors(State.errors.server))

    return lines
end

return MainView
