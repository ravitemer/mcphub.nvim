local M = {}
local slash_commands = require("mcphub.extensions.codecompanion.slash_commands")
local tools = require("mcphub.extensions.codecompanion.tools")
local variables = require("mcphub.extensions.codecompanion.variables")

---@param opts MCPHubCodeCompanionConfig
function M.setup(opts)
    opts = vim.tbl_deep_extend("force", {
        make_tools = true,
        show_server_tools_in_chat = true,
        show_result_in_chat = true,
        make_vars = true,
        make_slash_commands = true,
    }, opts or {})
    local ok, cc_config = pcall(require, "codecompanion.config")
    if not ok then
        return
    end
    ---Add @mcp group with `use_mcp_tool` and `access_mcp_resource` tools
    local static_tools = tools.create_static_tools(opts)
    cc_config.strategies.chat.tools = vim.tbl_deep_extend("force", cc_config.strategies.chat.tools, static_tools)

    ---Make each MCP server into groups and each tool from MCP server into function tools with proper namespacing
    tools.setup_dynamic_tools(opts)

    --- Make MCP resources into chat #variables
    variables.setup(opts)

    --- Make MCP prompts into slash commands
    slash_commands.setup(opts)
end

return M
