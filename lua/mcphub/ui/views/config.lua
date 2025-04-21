---@brief [[
--- Config view for MCPHub UI
--- Shows MCP server configurations
---@brief ]]
local NuiLine = require("mcphub.utils.nuiline")
local State = require("mcphub.state")
local Text = require("mcphub.utils.text")
local View = require("mcphub.ui.views.base")
local utils = require("mcphub.utils")
local validation = require("mcphub.utils.validation")

---@class ConfigView
---@field super View
local ConfigView = setmetatable({}, {
    __index = View,
})
ConfigView.__index = ConfigView

function ConfigView:new(ui)
    local self = View:new(ui, "config") -- Create base view with name
    return setmetatable(self, ConfigView)
end

function ConfigView:before_enter()
    View.before_enter(self)

    self.keymaps = {
        ["e"] = {
            action = function()
                if State.config and State.config.config then
                    self.ui:toggle()
                    vim.cmd("edit " .. State.config.config)
                else
                    vim.notify("No configuration file available", vim.log.levels.ERROR)
                end
            end,
            desc = "Edit config",
        },
    }
end

function ConfigView:get_initial_cursor_position()
    -- Position at start of server configurations
    local lines = self:render_header()
    if State.config and State.config.config then
        table.insert(
            lines,
            Text.pad_line(
                NuiLine()
                    :append("Config File: ", Text.highlights.muted)
                    :append(State.config.config, Text.highlights.info)
            )
        )
    end
    return #lines + 1
end

-- function ConfigView:after_enter()
--     self:unlock()
-- end

-- function ConfigView:before_leave()
--     self:lock()
-- end

function ConfigView:render()
    -- Get base header
    local lines = self:render_header(false)
    local width = self:get_width()

    -- Show config file path
    if State.config and State.config.config then
        local file_line =
            NuiLine():append("Config File: ", Text.highlights.muted):append(State.config.config, Text.highlights.info)
        table.insert(lines, Text.pad_line(file_line))
    else
        table.insert(
            lines,
            Text.pad_line(
                NuiLine()
                    :append("Config File: ", Text.highlights.muted)
                    :append("Not configured", Text.highlights.warning)
            )
        )
    end

    -- Add separator
    table.insert(lines, self:divider())
    table.insert(lines, Text.empty_line())

    local file_validation = validation.validate_config_file(State.config.config)
    if not file_validation.ok then
        table.insert(lines, Text.pad_line(NuiLine():append(file_validation.error.message, Text.highlights.error)))
        table.insert(lines, Text.empty_line())
    end

    if file_validation.json then
        -- Show file content
        -- vim.list_extend(
        --     lines,
        --     vim.tbl_map(Text.pad_line, Text.multiline(Text.render_json(file_validation.content), Text.highlights.muted))
        -- )
        vim.list_extend(lines, Text.render_json(file_validation.content))
    end
    return lines
end

return ConfigView
