if vim.g.loaded_mcphub then
    return
end
vim.g.loaded_mcphub = true

local hl = require("mcphub.utils.highlights")
hl.setup()
