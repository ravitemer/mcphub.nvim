local Base = require("mcphub.ui.capabilities.base")
local NuiLine = require("mcphub.utils.nuiline")
local State = require("mcphub.state")
local Text = require("mcphub.utils.text")
local highlights = require("mcphub.utils.highlights").groups
local native = require("mcphub.native")

---@class CustomInstructionsHandler : CapabilityHandler
---@field super CapabilityHandler
local CustomInstructionsHandler = setmetatable({}, {
    __index = Base,
})
CustomInstructionsHandler.__index = CustomInstructionsHandler
CustomInstructionsHandler.type = "customInstructions"

function CustomInstructionsHandler:new(server_name, capability_info, view)
    local handler = Base.new(self, server_name, capability_info, view)
    return handler
end

function CustomInstructionsHandler:handle_instructions_update(content)
    local is_native = native.is_native_server(self.server_name)
    local server_config = (
        is_native and State.native_servers_config[self.server_name] or State.servers_config[self.server_name]
    ) or {}
    local custom_instructions = server_config.custom_instructions or {}

    if State.hub_instance then
        State.hub_instance:update_server_config(self.server_name, {
            custom_instructions = vim.tbl_extend("force", custom_instructions, { text = content }),
        })
    end
end

function CustomInstructionsHandler:handle_action(line)
    local type = self:get_line_info(line)
    if type == "edit" then
        -- Get current instructions
        local is_native = native.is_native_server(self.server_name)
        local server_config = (
            is_native and State.native_servers_config[self.server_name] or State.servers_config[self.server_name]
        ) or {}
        local custom_instructions = server_config.custom_instructions or {}
        local text = custom_instructions.text or ""

        -- Open text box using base class method
        self:open_text_box("Custom Instructions", text, function(content)
            if content ~= text then
                self:handle_instructions_update(content)
            end
        end)
    end
end

function CustomInstructionsHandler:render(line_offset)
    line_offset = line_offset or 0
    self:clear_line_tracking()

    local lines = {}

    -- Custom Instructions info section
    vim.list_extend(lines, self:render_section_start(Text.icons.instructions .. " Custom Instructions"))

    local is_native = native.is_native_server(self.server_name)
    local server_config = (
        is_native and State.native_servers_config[self.server_name] or State.servers_config[self.server_name]
    ) or {}
    local custom_instructions = server_config.custom_instructions or {}
    local is_disabled = custom_instructions.disabled
    local text = custom_instructions.text or ""

    -- Status line
    local details = {}

    -- Add spacer
    table.insert(details, NuiLine():append(""))
    if text ~= "" then
        -- Add instructions text
        vim.list_extend(details, Text.multiline(text, is_disabled and highlights.muted or highlights.info))
    else
        -- Add instructions text
        vim.list_extend(details, Text.multiline("No custom instructions added.", highlights.muted))
    end

    vim.list_extend(lines, self:render_section_content(details, 2))
    vim.list_extend(lines, self:render_section_end())

    -- Actions section
    table.insert(lines, Text.pad_line(NuiLine()))
    vim.list_extend(lines, self:render_section_start("Actions"))

    local edit_line = NuiLine():append("[ " .. Text.icons.edit .. " Edit ]", highlights.success_fill)
    vim.list_extend(lines, self:render_section_content({ NuiLine(), edit_line }, 2))
    -- Track button line for interaction
    self:track_line(line_offset + #lines, "edit")

    vim.list_extend(lines, self:render_section_end())

    return lines
end

return CustomInstructionsHandler
