local Base = require("mcphub.ui.capabilities.base")
local NuiLine = require("mcphub.utils.nuiline")
local Text = require("mcphub.utils.text")
local highlights = require("mcphub.utils.highlights").groups
local Installers = require("mcphub.utils.installers")
local prompt_utils = require("mcphub.utils.prompt")

---@class CreateServerHandler : CapabilityHandler
---@field super CapabilityHandler
local CreateServerHandler = setmetatable({}, { __index = Base })
CreateServerHandler.__index = CreateServerHandler
CreateServerHandler.type = "create_server"

function CreateServerHandler:new(server_name, capability_info, view)
    local handler = Base.new(self, server_name, capability_info, view)
    return handler
end

function CreateServerHandler:handle_action(line)
    local type = self:get_line_info(line)
    if type == "install" then
        -- Get available installers
        local available = {}
        for id, installer in pairs(Installers) do
            if installer.check() then
                table.insert(available, {
                    id = id,
                    name = installer.name,
                })
            end
        end

        if #available > 0 then
            vim.ui.select(available, {
                prompt = "Choose installer:",
                format_item = function(item)
                    return item.name
                end,
            }, function(choice)
                if choice then
                    local installer = Installers[choice.id]
                    if installer then
                        self.view.ui:cleanup()
                        installer:create_native_server()
                    end
                end
            end)
        else
            vim.notify("No installers available. Please install CodeCompanion or Avante.", vim.log.levels.ERROR)
        end
    end
end

function CreateServerHandler:render(line_offset)
    line_offset = line_offset or 0
    self:clear_line_tracking()

    local lines = {}

    -- Description text
    local description = {
        "Native Lua servers allow you to create custom MCP-compatible servers directly in Lua.",
        "These servers can provide tools and resources that integrate seamlessly with mcphub.nvim.",
        "Perfect for plugin-specific functionality, file operations, or any custom Neovim integration.",
        "Create your own server to extend mcphub with your unique tools and resources.",
    }

    for _, line in ipairs(description) do
        table.insert(lines, Text.pad_line(line, highlights.muted))
    end

    table.insert(lines, Text.empty_line())
    table.insert(lines, self.view:divider())
    table.insert(lines, Text.empty_line())

    local install_line = NuiLine()
        :append(" " .. Text.icons.install .. " ", highlights.active_item)
        :append("Install", highlights.active_item)
        :append(" with: ", highlights.muted)

    -- Check each installer
    for id, installer in pairs(Installers) do
        if installer.check() then
            install_line
                :append("[" .. installer.name .. "]", highlights.success)
                :append(" ", highlights.muted)
                :append(Text.icons.check, highlights.success)
                :append("  ", highlights.muted)
        else
            install_line
                :append("[" .. installer.name .. "]", highlights.error)
                :append(" ", highlights.muted)
                :append(Text.icons.uninstall, highlights.error)
                :append("  ", highlights.muted)
        end
    end

    table.insert(lines, Text.pad_line(install_line))
    -- Track install line for interaction
    self:track_line(#lines + line_offset, "install", {
        hint = "Press <CR> to select installer",
    })

    table.insert(lines, Text.empty_line())
    table.insert(lines, self.view:divider())
    table.insert(lines, Text.empty_line())

    -- Show the LLM prompt content
    local guide = prompt_utils.get_native_server_prompt()
    if guide then
        -- Add heading for the section
        table.insert(lines, Text.pad_line("Native Server Guide (LLM Prompt)", highlights.title))
        table.insert(lines, Text.empty_line())

        -- Format guide content with proper highlighting
        for line in vim.gsplit(guide, "\n") do
            if line:match("^#+ ") then
                -- Headers
                table.insert(lines, Text.pad_line(line, highlights.title))
            elseif line:match("^```") or line:match("^```lua") then
                -- Code block start
                table.insert(lines, Text.pad_line(line, highlights.title))
            elseif line:match("^```$") then
                -- Code block end
                table.insert(lines, Text.pad_line(line, highlights.title))
            else
                -- Regular text, preserving any markdown formatting
                table.insert(lines, Text.pad_line(line, highlights.muted))
            end
        end
    end

    return lines
end

return CreateServerHandler
