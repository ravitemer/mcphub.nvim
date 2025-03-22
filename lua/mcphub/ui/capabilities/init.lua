local M = {}

-- Load capability handlers
M.handlers = {
    tool = require("mcphub.ui.capabilities.tool"),
    resource = require("mcphub.ui.capabilities.resource"),
    resourceTemplate = require("mcphub.ui.capabilities.resourceTemplate"),
    customInstructions = require("mcphub.ui.capabilities.customInstructions"),
    createServer = require("mcphub.ui.capabilities.createServer"),
}

-- Create a new capability handler instance
---@param type string Capability type ("tool", "resource", "resourceTemplate", etc)
---@param server_name string Server name
---@param capability_info table Raw capability info from server
---@return CapabilityHandler Handler instance
function M.create_handler(type, server_name, capability_info, view)
    local HandlerClass = M.handlers[type]
    if not HandlerClass then
        error("Unknown capability type: " .. type)
    end
    return HandlerClass:new(server_name, capability_info, view)
end

return M
