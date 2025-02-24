---@brief [[
--- Error management for MCPHub
--- Provides error types, creation, and formatting
---@brief ]]
---@class MCPError
---@field type string The error category (SETUP/SERVER/RUNTIME)
---@field code string Specific error code
---@field message string Human-readable error message
---@field details? table Additional error context
---@field timestamp number Unix timestamp of error creation
local Error = {}
Error.__index = Error

-- Error type constants
Error.Types = {
    SETUP = {
        INVALID_CONFIG = "INVALID_CONFIG",
        INVALID_PORT = "INVALID_PORT",
        MISSING_DEPENDENCY = "MISSING_DEPENDENCY",
        VERSION_MISMATCH = "VERSION_MISMATCH",
        SERVER_START = "SERVER_START"
    },
    SERVER = {
        CONNECTION = "CONNECTION",
        HEALTH_CHECK = "HEALTH_CHECK",
        API_ERROR = "API_ERROR",
        TIMEOUT = "TIMEOUT"
    },
    RUNTIME = {
        INVALID_STATE = "INVALID_STATE",
        RESOURCE_ERROR = "RESOURCE_ERROR",
        OPERATION_FAILED = "OPERATION_FAILED"
    }
}

--- Create a new error instance
--- @param type string The error category (SETUP/SERVER/RUNTIME)
--- @param code string Specific error code from Error.Types
--- @param message string Human-readable error message
--- @param details? table Additional error context
--- @return MCPError
function Error.init(type, code, message, details)
    return setmetatable({
        type = type,
        code = code,
        message = message,
        details = details or {},
        timestamp = vim.loop.now()
    }, Error)
end

--- Convert error to string representation
function Error:__tostring()
    local str = string.format("[%s.%s] %s", self.type, self.code, self.message)
    if not vim.tbl_isempty(self.details) then
        str = str .. "\nDetails: " .. vim.inspect(self.details)
    end
    return str
end

--- Constructor using __call metamethod
setmetatable(Error, {
    __call = function(_, ...)
        return Error.init(...)
    end
})

return Error
