local mcphub = require("mcphub")

-- Create base neovim server
mcphub.add_server("neovim", {
    displayName = "Neovim",
})

-- require("mcphub.native.neovim.terminal") -- Terminal and shell commands
require("mcphub.native.neovim.files") -- File system operations
require("mcphub.native.neovim.lsp") -- File system operations
