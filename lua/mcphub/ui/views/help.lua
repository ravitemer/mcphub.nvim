---@brief [[
--- Help view for MCPHub UI
--- Shows plugin documentation and keybindings
---@brief ]]
local Text = require("mcphub.utils.text")
local View = require("mcphub.ui.views.base")

---@class HelpView:View
---@field active_tab string Currently active tab
local HelpView = setmetatable({}, {
    __index = View,
})
HelpView.__index = HelpView

function HelpView:new(ui)
    ---@class View
    local instance = View:new(ui, "help")
    instance.tabs = {
        { id = "welcome", text = "Welcome" },
        { id = "troubleshooting", text = "Troubleshooting" },
        { id = "native", text = "Native Servers" },
        { id = "changelog", text = "Changelog" },
    }
    instance.active_tab = instance.tabs[1].id
    instance = setmetatable(instance, HelpView)
    return instance
end

function HelpView:cycle_tab()
    for i, tab in ipairs(self.tabs) do
        if tab.id == self.active_tab then
            -- Move to next tab or wrap around to first
            self.active_tab = (self.tabs[i + 1] or self.tabs[1]).id
            break
        end
    end
end

function HelpView:cycle_tab_reverse()
    for i, tab in ipairs(self.tabs) do
        if tab.id == self.active_tab then
            -- Move to previous tab or wrap around to last
            self.active_tab = (self.tabs[i - 1] or self.tabs[#self.tabs]).id
            break
        end
    end
end

function HelpView:render_tabs()
    local tabs = vim.tbl_map(function(tab)
        return {
            text = tab.text,
            selected = self.active_tab == tab.id,
        }
    end, self.tabs)
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
                self:cycle_tab()
                self:draw()
            end,
            desc = "Next tab",
        },
        ["<S-Tab>"] = {
            action = function()
                self:cycle_tab_reverse()
                self:draw()
            end,
            desc = "Previous tab",
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
    if self.active_tab == "welcome" then
        -- Welcome message
        local welcome_content = [[
# Welcome to MCPHub!

MCP Hub is a MCP client for neovim that seamlessly integrates [MCP (Model Context Protocol)](https://modelcontextprotocol.io/) servers into your editing workflow. It provides an intuitive interface for managing, testing, and using MCP servers with your favorite chat plugins.

> Visit [Documentation](https://ravitemer.github.io/mcphub.nvim/) site for detailed instructions on how to use MCPHub.

## Support Development

MCPHub is an open-source project that relies on community support. Your support helps maintain and enhance the plugin.

- [GitHub Sponsors](https://github.com/sponsors/ravitemer)
- [Buy me a coffee](https://www.buymeacoffee.com/ravitemer)
- [⭐ Star us on GitHub](https://github.com/ravitemer/mcphub.nvim)

### Get Help & Contribute
- [View Documentation](https://ravitemer.github.io/mcphub.nvim/) - Learn more about MCPHub
- [Discord Community](https://discord.gg/NTqfxXsNuN) - Get help and discuss features
- [Open a Discussion](https://github.com/ravitemer/mcphub.nvim/discussions) - Ask questions and share ideas
- [Create an Issue](https://github.com/ravitemer/mcphub.nvim/issues) - Report bugs
- [Report Security Issues](https://github.com/ravitemer/mcphub.nvim/blob/main/SECURITY.md)

### Share with the Community
- Create your own Native MCP Servers and share them in [Show and Tell](https://github.com/ravitemer/mcphub.nvim/discussions/categories/show-and-tell)
- Share your custom workflows and setups in [Native Servers](https://github.com/ravitemer/mcphub.nvim/discussions/categories/native-servers)
- Help others by sharing your configuration tips and tricks
- Showcase your innovative uses of MCPHub

### Join & Connect
- [Discord Community](https://discord.gg/NTqfxXsNuN) - Get help and discuss features
- [Follow on Twitter](https://x.com/ravitemer) - Stay updated on new releases
- Star the repository to show your support!

### Stay Updated
- Check the **Changelog** tab for latest features
- Watch **Discussions** for announcements and community showcases
- Browse **Marketplace** for new MCP servers
]]
        vim.list_extend(lines, Text.render_markdown(welcome_content))
    elseif self.active_tab == "troubleshooting" then
        local troubleshooting_content = prompt_utils.get_troubleshooting_guide()
        vim.list_extend(lines, Text.render_markdown(troubleshooting_content))
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
