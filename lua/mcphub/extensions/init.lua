local M = {}

---@alias MCPHub.Extensions.Type "avante" | "codecompanion"
---@alias MCPHub.ActionType "use_mcp_tool" | "access_mcp_resource"

---@class MCPHub.Extensions.AvanteConfig
---@field enabled boolean Whether the extension is enabled or not
---@field make_slash_commands boolean Whether to make slash commands or not

---@class MCPHub.Extensions.CodeCompanionConfig
---@field enabled boolean Whether the extension is enabled or not
---@field make_vars boolean Whether to make variables or not
---@field add_mcp_prefix_to_tool_names boolean Whether to add MCP prefix to tool names , resources and slash commands
---@field make_slash_commands boolean Whether to make slash commands or not
---@field make_tools boolean Whether to make individual tools and server groups or not
---@field show_server_tools_in_chat boolean Whether to show all tools in cmp or not
---@field show_result_in_chat boolean Whether to show the result in chat or not

---@class MCPHub.Extensions.Config
---@field avante MCPHub.Extensions.AvanteConfig Configuration for the Avante extension
---NOTE: Codecompanion setup is handled via mcphub extensions for codecompanion

---@param config MCPHub.Extensions.Config
function M.setup(config)
    local avante_config = config.avante or {}
    if avante_config.enabled then
        local ok, _ = pcall(require, "avante")
        if ok then
            local avante_ext = require("mcphub.extensions.avante")
            avante_ext.setup(avante_config)
        end
    end
end

return M
