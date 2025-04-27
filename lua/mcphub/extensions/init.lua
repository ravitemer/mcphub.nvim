local M = {}

function M.setup(extension, config)
    local shared = require("mcphub.extensions.shared")
    if not config.enabled then
        return
    end
    if extension == "avante" then
        local ok, _ = pcall(require, "avante")
        if not ok then
            return
        end
        shared.setup_avante_slash_commands(config.make_slash_commands)
    end
end

return M
