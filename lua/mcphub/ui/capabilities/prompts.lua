local Base = require("mcphub.ui.capabilities.base")
local NuiLine = require("mcphub.utils.nuiline")
local State = require("mcphub.state")
local Text = require("mcphub.utils.text")
local highlights = require("mcphub.utils.highlights").groups

---@class PromptsHandler : CapabilityHandler
---@field super CapabilityHandler
local PromptsHandler = setmetatable({}, {
    __index = Base,
})
PromptsHandler.__index = PromptsHandler
PromptsHandler.type = "prompts"

function PromptsHandler:new(server_name, capability_info, view)
    local handler = Base.new(self, server_name, capability_info, view)
    return handler
end

function PromptsHandler:render(line_offset)
    line_offset = line_offset or 0
    self:clear_line_tracking()

    local lines = {}
    local hub = State.hub_instance
    if not hub or not hub:is_ready() then
        vim.list_extend(lines, self:render_section_start("System Prompts"))
        vim.list_extend(lines, self:render_section_content({ NuiLine():append("Hub not ready", highlights.error) }, 2))
        vim.list_extend(lines, self:render_section_end())
        return lines
    end

    local prompts = hub:get_prompts()
    if not prompts then
        vim.list_extend(lines, self:render_section_start("System Prompts"))
        vim.list_extend(
            lines,
            self:render_section_content({ NuiLine():append("No prompts available", highlights.muted) }, 2)
        )
        vim.list_extend(lines, self:render_section_end())
        return lines
    end

    -- Active Servers Section
    if prompts.active_servers then
        vim.list_extend(lines, self:render_section_start("Active Servers Prompt", highlights.title))
        vim.list_extend(lines, self:render_section_content(Text.multiline(prompts.active_servers), 2))
        vim.list_extend(lines, self:render_section_end())
        table.insert(lines, Text.empty_line())
    end

    -- Tool Usage Section
    if prompts.use_mcp_tool then
        vim.list_extend(lines, self:render_section_start("Tool Usage Prompt", highlights.title))
        vim.list_extend(lines, self:render_section_content(Text.multiline(prompts.use_mcp_tool), 2))
        vim.list_extend(lines, self:render_section_end())
        table.insert(lines, Text.empty_line())
    end

    -- Resource Access Section
    if prompts.access_mcp_resource then
        vim.list_extend(lines, self:render_section_start("Resource Access Prompt", highlights.title))
        vim.list_extend(lines, self:render_section_content(Text.multiline(prompts.access_mcp_resource), 2))
        vim.list_extend(lines, self:render_section_end())
    end

    return lines
end

return PromptsHandler
