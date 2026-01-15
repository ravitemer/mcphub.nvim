---@module "codecompanion"
--[[
*MCP Servers Tool adapted for function calling*
This tool can be used to call tools and resources from the MCP Servers.
--]]

local M = {}

---@param opts MCPHub.Extensions.CodeCompanionConfig
function M.setup(opts)
    opts = vim.tbl_deep_extend("force", {
        make_tools = true,
        show_server_tools_in_chat = true,
        add_mcp_prefix_to_tool_names = false,
        make_vars = true,
        make_slash_commands = true,
        show_result_in_chat = true,
    }, opts or {})
    local ok, cc_config = pcall(require, "codecompanion.config")
    if not ok then
        return
    end

    local tools = require("mcphub.extensions.codecompanion.tools")
    ---Add @mcp group with `use_mcp_tool` and `access_mcp_resource` tools
    local static_tools = tools.create_static_tools(opts)
    cc_config.interactions.chat.tools = vim.tbl_deep_extend("force", cc_config.interactions.chat.tools, static_tools)

    ---Make each MCP server into groups and each tool from MCP server into function tools with proper namespacing
    tools.setup_dynamic_tools(opts)

    --- Make MCP resources into chat #variables
    require("mcphub.extensions.codecompanion.variables").setup(opts)

    --- Make MCP prompts into slash commands
    require("mcphub.extensions.codecompanion.slash_commands").setup(opts)
end

return M
