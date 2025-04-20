local mcphub = require("mcphub")
local prompt_utils = require("mcphub.utils.prompt")

-- Create base mcphub server
mcphub.add_server("mcphub", {
    displayName = "MCPHub",
    description = "MCPHub server provides tools and resources to manage the mcphub.nvim neovim plugin. It has tools to toggle any MCP Server along with resources like docs, guides.",
})
require("mcphub.native.mcphub.guide")

mcphub.add_prompt("mcphub", {
    name = "create_native_server",
    description = "Create a native MCP server for mcphub.nvim",
    arguments = {
        {
            name = "mcphub_setup_file",
            description = "Path to file where mcphub.setup({}) is called.",
            default = vim.fn.stdpath("config") .. "/",
            required = true,
        },
    },
    handler = function(req, res)
        local guide = prompt_utils.get_native_server_prompt()
        local setup_file_path = req.params.mcphub_setup_file
        local is_codecompanion = req.caller.type == "codecompanion"
        local prompt = string.format(
            [[%s I have provided you a guide to create Lua native MCP servers for mcphub.nvim plugin. My Neovim config directory is `%s`. I have called mcphub.setup({}) in this file `%s`.

I want to create a native MCP server for mcphub.nvim plugin. The server should have the following capabilities:

]],
            is_codecompanion and "@mcp" or "",
            vim.fn.stdpath("config"),
            setup_file_path
        )
        res:user():text(guide):text(prompt)
        res:send()
    end,
})
