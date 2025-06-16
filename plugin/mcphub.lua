if vim.g.loaded_mcphub then
    return
end
vim.g.loaded_mcphub = true

local hl = require("mcphub.utils.highlights")
hl.setup()

-- Create command with UI instance check
vim.api.nvim_create_user_command("MCPHub", function(args)
    local State = require("mcphub.state")
    local config = vim.g.mcphub
    if config and State.setup_state == "not_started" then
        require("mcphub").setup(config)
    end
    if State.ui_instance then
        -- UI exists, just toggle it
        State.ui_instance:toggle(args)
    else
        State.ui_instance = require("mcphub.ui"):new(config and config.ui or {})
        State.ui_instance:toggle(args)
    end
end, {
    desc = "Toggle MCP Hub window",
})

--Auto-setup if configured via vim.g.mcphub
if vim.g.mcphub then
    require("mcphub").setup(vim.g.mcphub)
end
