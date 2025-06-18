local M = {}

---@alias MCPHubExtensionType "avante" | "codecompanion"

---@alias MCPHubToolType "use_mcp_tool" | "access_mcp_resource"

---@class MCPHubExtensionConfig
---@field enabled boolean Whether the extension is enabled or not

---@class MCPHubAvanteConfig : MCPHubExtensionConfig
---@field make_slash_commands boolean Whether to make slash commands or not

---@class MCPHubCodeCompanionConfig : MCPHubExtensionConfig
---@field make_vars boolean Whether to make variables or not
---@field make_slash_commands boolean Whether to make slash commands or not
---@field make_tools boolean Whether to make individual tools and server groups or not
---@field show_server_tools_in_chat boolean Whether to show all tools in cmp or not
---@field show_result_in_chat boolean Whether to show the result in chat or not

---@param extension MCPHubExtensionType
---@param config MCPHubAvanteConfig | MCPHubCodeCompanionConfig
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
