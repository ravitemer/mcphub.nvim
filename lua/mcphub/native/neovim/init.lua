local mcphub = require("mcphub")

-- Create base neovim server
mcphub.add_server("neovim", {
    displayName = "Neovim",
    description = "Neovim MCP server provides a set of tools and resources that integrate with neovim.",
})

require("mcphub.native.neovim.terminal") -- Terminal and shell commands
require("mcphub.native.neovim.files") -- File system operations
require("mcphub.native.neovim.lsp")
require("mcphub.native.neovim.prompts")
require("mcphub.native.neovim.test")
