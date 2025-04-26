local M = {}

--- @class LogConfig
--- @field log_level number Default log level
--- @field to_file boolean Whether to log to file
--- @field file_path? string Path to log file
--- @field prefix string Prefix for log messages
local config = {
    level = vim.log.levels.ERROR,
    to_file = false,
    file_path = nil,
    prefix = "MCPHub",
}

--- Setup logger configuration
--- @param opts LogConfig
function M.setup(opts)
    config = vim.tbl_deep_extend("force", config, opts or {})

    -- Create log directory if logging to file
    if config.to_file and config.file_path then
        local path = vim.fn.fnamemodify(config.file_path, ":h")
        vim.fn.mkdir(path, "p")
    end
end

--- Format structured message
--- @param msg string|table Message or structured data
--- @param level_str string Level string for log prefix
--- @return string formatted_message
local function format_message(msg, level_str)
    local str = ""
    if type(msg) == "table" then
        -- Handle structured logs (from server)
        if msg.code and msg.message then
            local base = string.format("[%s] %s", msg.code, msg.message)
            if msg.data then
                str = string.format("%s\nData: %s", base, vim.inspect(msg.data))
            else
                str = base
            end
        end
        -- Regular table data
        str = vim.inspect(msg)
    else
        str = msg
    end
    return str
end

--- Write to log file
--- @param formatted string Formatted message
--- @param level_str string Level string
--- @param level number Log level
--- @return boolean success Whether the write was successful
local function write_to_file(formatted, level_str, level)
    -- Only write if:
    -- 1. File logging is enabled and path is set
    -- 2. Level meets minimum configured level
    if not (config.to_file and config.file_path) or level < config.level then
        return false
    end

    local timestamp = os.date("%H:%M:%S")
    local log_line = string.format("(%s) %s [%s] %s\n", vim.fn.getpid(), timestamp, level_str, formatted)

    local f = io.open(config.file_path, "a")
    if f then
        f:write(log_line)
        f:close()
        return true
    end
    return false
end

--- Internal logging function
--- @param msg string|table Message or structured data
--- @param level number Log level
local function log_internal(msg, level)
    -- Early return if below configured level and not an error
    if level < config.level and level < vim.log.levels.ERROR then
        return
    end

    local level_str = ({
        [vim.log.levels.DEBUG] = "debug",
        [vim.log.levels.INFO] = "info",
        [vim.log.levels.WARN] = "warn",
        [vim.log.levels.ERROR] = "error",
        [vim.log.levels.TRACE] = "trace",
    })[level] or "unknown"

    local formatted = format_message(msg, level_str:upper())
    local wrote_to_file = write_to_file(formatted, level_str:upper(), level)

    -- Only notify if:
    -- 1. It's an error (always show errors) OR
    -- 2. Level meets minimum AND we didn't write to file
    if level >= vim.log.levels.ERROR or (level >= config.level and not wrote_to_file) then
        vim.schedule(function()
            vim.notify(formatted, level)
        end)
    end
end

--- Log a debug message
--- @param msg string|table
function M.debug(msg)
    log_internal(msg, vim.log.levels.DEBUG)
end

--- Log an info message
--- @param msg string|table
function M.info(msg)
    log_internal(msg, vim.log.levels.INFO)
end

--- Log a warning message
--- @param msg string|table
function M.warn(msg)
    log_internal(msg, vim.log.levels.WARN)
end

--- Log an error message
--- @param msg string|table
function M.error(msg)
    log_internal(msg, vim.log.levels.ERROR)
end

function M.trace(msg)
    log_internal(msg, vim.log.levels.TRACE)
end

return M
