local State = require("mcphub.state")
local prompt_utils = require("mcphub.utils.prompt")

-- Get installation prompt for marketplace servers
local function get_install_prompt(server)
    if not server or not server.mcpId then
        vim.notify("Invalid server data", vim.log.levels.ERROR)
        return nil
    end

    local details = State.marketplace_state.server_details[server.mcpId]
    if not details or not details.data then
        vim.notify("Server details not available", vim.log.levels.ERROR)
        return nil
    end

    return prompt_utils.get_marketplace_server_prompt({
        config_file = State.config.config,
        name = server.name,
        mcpId = server.mcpId,
        githubUrl = server.githubUrl,
        readmeContent = details.data.readmeContent,
    })
end
-- Installer definitions and helpers
local Installers = {
    avante = {
        name = "Avante",
        check = function()
            local ok = pcall(require, "avante")
            return ok
        end,
        install = function(self, server)
            local prompt = get_install_prompt(server)
            if not prompt then
                return
            end
            local sidebar = require("avante").get()
            sidebar:new_chat()
            sidebar:add_chat_history({
                role = "user",
                content = prompt,
            }, {
                visible = false,
            })
            local api = require("avante.api")
            api.ask({
                question = "@read_global_file @write_global_file Please follow the provided instructions carefully to install this MCP server",
                without_selection = true,
            })
        end,
        create_native_server = function(self)
            local guide = prompt_utils.get_native_server_prompt()
            if not guide then
                vim.notify("Native server guide not available", vim.log.levels.ERROR)
                return
            end
            local sidebar = require("avante").get()
            sidebar:new_chat()
            sidebar:add_chat_history({
                role = "user",
                content = guide,
            }, {
                visible = false,
            })
            local api = require("avante.api")
            api.ask({
                question = "I have provided you a guide to create Lua native MCP servers for mcphub.nvim plugin. My Neovim config directory is '"
                    .. vim.fn.stdpath("config")
                    .. "'. Once you understood the guide thoroughly, please ask me what kind of server, tools, or resources I want to create.",
                without_selection = true,
            })
        end,
    },
    codecompanion = {
        name = "CodeCompanion",
        check = function()
            local ok = pcall(require, "codecompanion")
            return ok
        end,
        install = function(self, server)
            local prompt = get_install_prompt(server)
            if not prompt then
                return
            end
            local cc_chat = require("codecompanion").chat()
            cc_chat:add_message({
                role = "user",
                content = prompt,
            }, {
                visible = false,
            })
            cc_chat:add_buf_message({
                role = "user",
                content = "@{files} @{cmd_runner} Please follow the provided instructions carefully to install this MCP server",
            })
        end,
        create_native_server = function(self)
            local guide = prompt_utils.get_native_server_prompt()
            if not guide then
                vim.notify("Native server guide not available", vim.log.levels.ERROR)
                return
            end
            local cc_chat = require("codecompanion").chat()
            cc_chat:add_message({
                role = "user",
                content = guide,
            }, {
                visible = false,
            })
            cc_chat:add_buf_message({
                role = "user",
                content = "@{mcp} I have provided you a guide to create Lua native MCP servers for mcphub.nvim plugin. My Neovim config directory is '"
                    .. vim.fn.stdpath("config")
                    .. "'. Once you understood the guide thoroughly, please ask me what kind of server, tools, or resources I want to create.",
            })
        end,
    },
}

return Installers
