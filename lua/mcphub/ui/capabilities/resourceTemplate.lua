local Base = require("mcphub.ui.capabilities.base")
local NuiLine = require("mcphub.utils.nuiline")
local State = require("mcphub.state")
local Text = require("mcphub.utils.text")
local highlights = require("mcphub.utils.highlights").groups

---@class ResourceTemplateHandler : CapabilityHandler
---@field super CapabilityHandler
local ResourceTemplateHandler = setmetatable({}, {
    __index = Base,
})
ResourceTemplateHandler.__index = ResourceTemplateHandler
ResourceTemplateHandler.type = "resourceTemplate"

function ResourceTemplateHandler:new(server_name, capability_info, view)
    local handler = Base.new(self, server_name, capability_info, view)
    handler.state = vim.tbl_extend("force", handler.state, {
        input_value = "",
    })
    return handler
end

function ResourceTemplateHandler:execute()
    -- Check if already executing
    if self.state.is_executing then
        vim.notify("Resource template access is already in progress", vim.log.levels.WARN)
        return
    end

    -- Set executing state
    self.state.is_executing = true
    self.state.error = nil
    self.view:draw()

    -- Access resource with user provided URI
    if State.hub_instance then
        State.hub_instance:access_resource(self.server_name, self.state.input_value, {
            parse_response = true,
            callback = function(response, err)
                self:handle_response(response, err)
                self.view:draw()
            end,
        })
    end
end

function ResourceTemplateHandler:handle_input_action()
    self:handle_input(string.format("URI: "), self.state.input_value, function(input)
        -- Update value
        self.state.input_value = input
        self.view:draw()
    end)
end

function ResourceTemplateHandler:handle_action(line)
    local type = self:get_line_info(line)
    if type == "submit" then
        self:execute()
    elseif type == "input" then
        self:handle_input_action()
    end
end

function ResourceTemplateHandler:render(line_offset)
    line_offset = line_offset or 0
    -- Clear previous line tracking
    self:clear_line_tracking()

    local lines = {}

    -- Resource template info section
    vim.list_extend(lines, self:render_section_start("Template Information"))

    -- Template details
    local details = {
        NuiLine()
            :append("Name: ", highlights.muted)
            :append(self.info.name or "N/A", self.info.name and highlights.success or highlights.muted),
        NuiLine():append("Template: ", highlights.muted):append(self.info.uriTemplate, highlights.info),
    }

    if self.info.mimeType then
        table.insert(details, NuiLine():append("Type: ", highlights.muted):append(self.info.mimeType, highlights.info))
    end

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

    -- Input field
    local input_line = NuiLine():append("> ", highlights.success):append(self.state.input_value or "", highlights.info)
    vim.list_extend(lines, self:render_section_content({ input_line }, 2))

    -- Track input line
    self:track_line(line_offset + #lines, "input")

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

return ResourceTemplateHandler
