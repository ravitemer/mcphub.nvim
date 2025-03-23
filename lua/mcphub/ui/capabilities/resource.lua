local Base = require("mcphub.ui.capabilities.base")
local NuiLine = require("mcphub.utils.nuiline")
local State = require("mcphub.state")
local Text = require("mcphub.utils.text")
local highlights = require("mcphub.utils.highlights").groups

---@class ResourceHandler : CapabilityHandler
---@field super CapabilityHandler
local ResourceHandler = setmetatable({}, {
    __index = Base,
})
ResourceHandler.__index = ResourceHandler
ResourceHandler.type = "resource"

function ResourceHandler:new(server_name, capability_info, view)
    local handler = Base.new(self, server_name, capability_info, view)
    return handler
end

function ResourceHandler:execute()
    -- Check if already executing
    if self.state.is_executing then
        vim.notify("Resource access is already in progress", vim.log.levels.WARN)
        return
    end

    -- Set executing state
    self.state.is_executing = true
    self.state.error = nil
    self.view:draw()

    -- Access resource
    if State.hub_instance then
        State.hub_instance:access_resource(self.server_name, self.info.uri, {
            parse_response = true,
            callback = function(response, err)
                self:handle_response(response, err)
                self.view:draw()
            end,
        })
    end
end

function ResourceHandler:handle_action(line)
    local type = self:get_line_info(line)
    if type == "submit" then
        self:execute()
    end
end

function ResourceHandler:render(line_offset)
    line_offset = line_offset or 0
    -- Clear previous line tracking
    self:clear_line_tracking()

    local lines = {}

    -- Resource info section
    vim.list_extend(lines, self:render_section_start("Resource Information"))

    -- Resource details
    local details = {
        NuiLine()
            :append("Name: ", highlights.muted)
            :append(self.info.name or "N/A", self.info.name and highlights.success or highlights.muted),
        NuiLine():append("Type: ", highlights.muted):append(self.info.mimeType or "unknown", highlights.info),
        NuiLine():append("URI: ", highlights.muted):append(self.info.uri, highlights.link),
    }

    vim.list_extend(lines, self:render_section_content(details, 2))

    -- Description if any
    if self.info.description then
        table.insert(lines, Text.pad_line(NuiLine():append("│", highlights.muted)))
        vim.list_extend(lines, self:render_section_content(Text.multiline(self.info.description, highlights.muted), 2))
    end

    vim.list_extend(lines, self:render_section_end())

    -- Action section
    table.insert(lines, Text.pad_line(NuiLine()))
    vim.list_extend(lines, self:render_section_start("Access Resource"))

    -- Action button
    local button_line
    if self.state.is_executing then
        button_line = NuiLine()
            :append("[ ", highlights.muted)
            :append("Processing...", highlights.muted)
            :append(" ]", highlights.muted)
    else
        button_line = NuiLine()
            :append("[ ", highlights.success_fill)
            :append("Access", highlights.success_fill)
            :append(" ]", highlights.success_fill)
    end
    vim.list_extend(lines, self:render_section_content({ NuiLine():append(" "), button_line }, 2))

    -- Track submit line for interaction
    self:track_line(line_offset + #lines, "submit")

    -- Error message if any
    if self.state.error then
        table.insert(lines, Text.pad_line(NuiLine():append("│", highlights.muted)))
        local error_lines = Text.multiline(self.state.error, highlights.error)
        vim.list_extend(lines, self:render_section_content(error_lines, 2))
    end

    vim.list_extend(lines, self:render_section_end())

    -- Result section if any
    vim.list_extend(lines, self:render_result())

    return lines
end

return ResourceHandler
