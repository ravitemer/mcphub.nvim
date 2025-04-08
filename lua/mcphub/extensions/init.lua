local utils = require("mcphub.extensions.utils")
local M = {}

function M.setup(extension, config)
    if extension == "codecompanion" then
        utils.setup_codecompanion_variables(config.make_vars)
        utils.setup_codecompanion_slash_commands(config.make_slash_commands)
        -- utils.setup_codecompanion_tools(config.make_tools)
    end
    --TODO: Support for Avante
    if extension == "avante" then
        utils.setup_avante_slash_commands(config.make_slash_commands)
    end
end

return M
