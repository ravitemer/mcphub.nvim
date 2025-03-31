local mcphub = require("mcphub")
local prompt_utils = require("mcphub.utils.prompt")

mcphub.add_resource("neovim", {
    name = "MCPHub Plugin Docs",
    mimeType = "text/plain",
    uri = "mcphub://docs",
    description = [[Documentation for the mcphub.nvim plugin for Neovim.]],
    handler = function(_, res)
        local guide = prompt_utils.get_plugin_docs()
        if not guide then
            return res:error("Plugin docs not available")
        end
        return res:text(guide):send()
    end,
})

mcphub.add_resource("neovim", {
    name = "MCPHub Native Server Guide",
    mimeType = "text/plain",
    uri = "mcphub://native-server/guide",
    description = [[Documentation on how to create Lua Native MCP servers for mcphub.nvim plugin.
This guide is intended for Large language models to help users create their own native servers for mcphub.nvim plugin.
Access this guide whenever you need information on how to create a native server for mcphub.nvim plugin.]],
    handler = function(_, res)
        local guide = prompt_utils.get_native_server_prompt()
        if not guide then
            return res:error("Native server guide not available")
        end
        return res:text(guide):send()
    end,
})

mcphub.add_resource("neovim", {
    name = "MCPHub Changelog",
    mimeType = "text/plain",
    uri = "mcphub://changelog",
    description = [[Changelog for the mcphub.nvim plugin for Neovim.]],
    handler = function(_, res)
        local guide = prompt_utils.get_plugin_changelog()
        if not guide then
            return res:error("Plugin changelog not available")
        end
        return res:text(guide):send()
    end,
})
