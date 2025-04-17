local M = {}

function M.setup(extension, config)
    local shared = require("mcphub.extensions.shared")
    if not config.enabled then
        return
    end

    if extension == "codecompanion" then
        local ok, cc_config = pcall(require, "codecompanion.config")
        if not ok then
            return
        end
        local mcp_extension = require("mcphub.extensions.codecompanion")
        cc_config.strategies.chat.tools =
            vim.tbl_deep_extend("force", cc_config.strategies.chat.tools, mcp_extension.create_tools())
        shared.setup_codecompanion_variables(config.make_vars)
        shared.setup_codecompanion_slash_commands(config.make_slash_commands)
        -- shared.setup_codecompanion_tools(config.make_tools)
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
