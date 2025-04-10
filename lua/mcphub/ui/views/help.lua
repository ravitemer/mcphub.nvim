---@brief [[
--- Help view for MCPHub UI
--- Shows plugin documentation and keybindings
---@brief ]]
local NuiLine = require("mcphub.utils.nuiline")
local Text = require("mcphub.utils.text")
local View = require("mcphub.ui.views.base")

---@class HelpView
---@field super View
---@field active_tab "readme"|"native"|"changelog" Currently active tab
local HelpView = setmetatable({}, {
    __index = View,
})
HelpView.__index = HelpView

function HelpView:new(ui)
    local self = View:new(ui, "help")
    self.tabs = {
        { id = "welcome", text = "Welcome" },
        { id = "troubleshooting", text = "Troubleshooting" },
        { id = "readme", text = "README" },
        { id = "native", text = "Native Servers" },
        { id = "changelog", text = "Changelog" },
    }
    self.active_tab = self.tabs[1].id
    self = setmetatable(self, HelpView)
    return self
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
            desc = "Switch tab",
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

A powerful Neovim plugin that integrates MCP (Model Context Protocol) servers into your workflow. Configure and manage MCP servers through a centralized config file while providing an intuitive UI for browsing, installing and testing tools and resources.

## Support Development

MCPHub is an open-source project that relies on community support to stay active and improve. Your support helps maintain and enhance the plugin.

- [GitHub Sponsors](https://github.com/sponsors/ravitemer)
- [Buy me a coffee](https://www.buymeacoffee.com/ravitemer)
- [⭐ Star us on GitHub](https://github.com/ravitemer/mcphub.nvim)

## Quick Links

### Get Help & Contribute
- [Open a Discussion](https://github.com/ravitemer/mcphub.nvim/discussions) - Ask questions and share ideas
- [Create an Issue](https://github.com/ravitemer/mcphub.nvim/issues) - Report bugs
- [Report Security Issues](https://github.com/ravitemer/mcphub.nvim/blob/main/SECURITY.md)
- [View Documentation](lua/mcphub/native/README.md) - Learn more about MCPHub

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
        local troubleshooting_content = [[
# 🔨 Troubleshooting

1. **Environment Requirements**

   - Ensure these are installed as they're required by most MCP servers:
     ```bash
     node --version    # Should be >= 18.0.0
     python --version  # Should be installed
     uvx --version    # Should be installed
     ```
   - Most server commands use `npx` or `uvx` - verify these work in your terminal

2. LLM Model Issues

   If the LLM isn't making correct tool calls:

   1. **Schema Support**
   - Models with function calling support (like claude-3.5) work best with Avante's schema format
   - Only top-tier models handle XML-based tool formats correctly
   - Consider upgrading to a better model if seeing incorrect tool usage

   2. **Common Tool Call Issues**
   - Missing `action` field
   - Incorrect `server_name`
   - Missing `tool_name` or `uri`
   - Malformed arguments

   3. **Recommended Models**
   - GPT-4o
   - Claude 3.5 Sonnet
   - Claude 3.7
   - Gemini 2.0 Flash
   - Gemini 2.0 Pro
   - Mistral Large

3. **Port Issues**

   - If you get `EADDRINUSE` error, kill the existing process:
     ```bash
     lsof -i :[port]  # Find process ID
     kill [pid]       # Kill the process
     ```

4. **Configuration File**

   - Ensure config path is absolute
   - Verify file contains valid JSON with `mcpServers` key
   - Check server-specific configuration requirements
   - Validate server command and args are correct for your system

5. **MCP Server Issues**

   - Validate server configurations using either:
     - [MCP Inspector](https://github.com/modelcontextprotocol/inspector): GUI tool for verifying server operation
     - [mcp-cli](https://github.com/wong2/mcp-cli): Command-line tool for testing servers with config files
   - Check server logs in MCPHub UI (Logs view)
   - Test tools and resources individually to isolate issues

6. **Need Help?**
   - First try testing it with [minimal.lua](https://gist.github.com/ravitemer/c85d69542bdfd1a45c6a9849301e4388) 
   - Feel free to open an [Issue](https://github.com/ravitemer/mcphub.nvim/issues) for bugs or doubts
   - Create a [Discussion](https://github.com/ravitemer/mcphub.nvim/discussions) for questions, showcase, or feature requests

Note: You can also access the Express server directly at `http://localhost:[config.port]` or at `config.server_url`
]]
        vim.list_extend(lines, Text.render_markdown(troubleshooting_content))
    elseif self.active_tab == "readme" then
        local readme = prompt_utils.get_plugin_docs()
        if readme then
            vim.list_extend(lines, Text.render_markdown(readme))
        else
            table.insert(lines, Text.pad_line("README not found", Text.highlights.error))
        end
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
