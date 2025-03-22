local M = require("lualine.component"):extend()

-- Initialize the component
function M:init(options)
    M.super.init(self, options)
    self.options = vim.tbl_extend("keep", self.options or {}, {
        icon = "🔌",
        color = { fg = "#8FBCBB" },
    })
end

-- Update function that lualine will call
function M:update_status()
    local hub = require("mcphub").get_hub_instance()
    if hub == nil then
        return "MCP: N/A"
    end
    local active_servers = #hub:get_servers()
    return string.format("MCP: %d", active_servers)
end

return M
