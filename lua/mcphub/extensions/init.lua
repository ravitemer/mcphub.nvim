local utils = require("mcphub.extensions.utils")
local M = {}

function M.setup(extension, config)
    if extension == "codecompanion" then
        utils.setup_codecompanion_variables(config.make_vars)
        -- utils.setup_codecompanion_tools(config.make_tools)
    end
    --TODO: Support for Avante
end

return M
