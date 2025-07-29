---@module "copilotchat"
--[[
This extension integrates MCP servers with CopilotChat.nvim by converting
MCP tools and resources into CopilotChat functions.
--]]

local M = {}

---@param opts MCPHub.Extensions.CopilotChatConfig
function M.setup(opts)
    opts = vim.tbl_deep_extend("force", {
        convert_tools_to_functions = true,
        convert_resources_to_functions = true,
        add_mcp_prefix = false,
    }, opts or {})

    -- Check if CopilotChat is available
    local ok, _ = pcall(require, "CopilotChat")
    if not ok then
        return
    end

    -- Setup tools and resources
    require("mcphub.extensions.copilotchat.functions").setup(opts)
end

return M
