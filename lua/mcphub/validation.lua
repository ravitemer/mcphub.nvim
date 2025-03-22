---@brief [[
--- Validation utilities for MCPHub
--- Handles configuration and input validation
---@brief ]]
local Error = require("mcphub.errors")
local version = require("mcphub.version")

local M = {}

---@class ValidationResult
---@field ok boolean
---@field error? MCPError

--- Validate setup options
---@param opts table
---@return ValidationResult
function M.validate_setup_opts(opts)
    if not opts.port then
        return {
            ok = false,
            error = Error("SETUP", Error.Types.SETUP.INVALID_PORT, "Port is required for MCPHub setup"),
        }
    end

    if not opts.config then
        return {
            ok = false,
            error = Error("SETUP", Error.Types.SETUP.INVALID_CONFIG, "Config file path is required"),
        }
    end

    -- Validate cmd and cmdArgs if provided
    if opts.cmd and type(opts.cmd) ~= "string" then
        return {
            ok = false,
            error = Error("SETUP", Error.Types.SETUP.INVALID_CMD, "cmd must be a string"),
        }
    end

    if opts.cmdArgs and type(opts.cmdArgs) ~= "table" then
        return {
            ok = false,
            error = Error("SETUP", Error.Types.SETUP.INVALID_CMD_ARGS, "cmdArgs must be an array"),
        }
    end

    -- Validate config file
    local file_result = M.validate_config_file(opts.config)
    if not file_result.ok then
        return file_result
    end

    return {
        ok = true,
    }
end

local function validate_custom_instructions(custom_instructions)
    if type(custom_instructions) ~= "table" then
        return false
    end

    -- Validate text field if present
    if custom_instructions.text ~= nil and type(custom_instructions.text) ~= "string" then
        return false
    end

    -- Validate disabled field if present
    if custom_instructions.disabled ~= nil and type(custom_instructions.disabled) ~= "boolean" then
        return false
    end

    return true
end

--- Validate MCP config file
---@param path string
---@return ValidationResult
function M.validate_config_file(path)
    if not path then
        return {
            ok = false,
            error = Error("SETUP", Error.Types.SETUP.INVALID_CONFIG, "Config file path is required"),
        }
    end
    -- Create config directory if it doesn't exist
    local config_dir = vim.fn.fnamemodify(path, ":h")
    if vim.fn.isdirectory(config_dir) == 0 then
        vim.fn.mkdir(config_dir, "p")
    end

    -- Try to read existing config file
    local file = io.open(path, "r")
    local content

    if not file then
        -- Create new config file with empty mcpServers object
        content = [[{
  "mcpServers": {}
}]]
        local new_file = io.open(path, "w")
        if not new_file then
            return {
                ok = false,
                error = Error(
                    "SETUP",
                    Error.Types.SETUP.INVALID_CONFIG,
                    string.format("Failed to create config file: %s", path)
                ),
            }
        end
        new_file:write(content)
        new_file:close()
    else
        content = file:read("*a")
        file:close()
    end

    local success, json = pcall(vim.json.decode, content)
    if not success then
        return {
            ok = false,
            content = content,
            error = Error(
                "SETUP",
                Error.Types.SETUP.INVALID_CONFIG,
                string.format("Invalid JSON in config file: %s", path),
                {
                    parse_error = json,
                }
            ),
        }
    end

    if not json.mcpServers or type(json.mcpServers) ~= "table" then
        return {
            ok = false,
            content = content,
            error = Error(
                "SETUP",
                Error.Types.SETUP.INVALID_CONFIG,
                string.format("Config file must contain 'mcpServers' object: %s", path)
            ),
        }
    end

    -- Validate disabled_tools and custom_instructions for each server
    for server_name, server_config in pairs(json.mcpServers) do
        -- Validate disabled_tools if present
        if server_config.disabled_tools ~= nil then
            if type(server_config.disabled_tools) ~= "table" then
                return {
                    ok = false,
                    content = content,
                    error = Error(
                        "SETUP",
                        Error.Types.SETUP.INVALID_CONFIG,
                        string.format("disabled_tools must be an array in server %s", server_name)
                    ),
                }
            end
            -- Validate each tool name is a string
            for _, tool_name in ipairs(server_config.disabled_tools) do
                if type(tool_name) ~= "string" or tool_name == "" then
                    return {
                        ok = false,
                        content = content,
                        error = Error(
                            "SETUP",
                            Error.Types.SETUP.INVALID_CONFIG,
                            string.format("disabled_tools must contain non-empty strings in server %s", server_name)
                        ),
                    }
                end
            end
        end

        -- Validate custom_instructions if present
        if server_config.custom_instructions ~= nil then
            if not validate_custom_instructions(server_config.custom_instructions) then
                return {
                    ok = false,
                    content = content,
                    error = Error(
                        "SETUP",
                        Error.Types.SETUP.INVALID_CONFIG,
                        string.format("Invalid custom_instructions format in server %s", server_name)
                    ),
                }
            end
        end
    end

    return {
        ok = true,
        json = json,
        content = content,
    }
end

--- Validate MCP Hub version
---@param ver_str string Version string to validate
---@return ValidationResult
function M.validate_version(ver_str)
    local major, minor, patch = ver_str:match("(%d+)%.(%d+)%.(%d+)")
    if not major then
        return {
            ok = false,
            error = Error("SETUP", Error.Types.SETUP.VERSION_MISMATCH, "Invalid version format", {
                version = ver_str,
            }),
        }
    end

    local current = {
        major = tonumber(major),
        minor = tonumber(minor),
        patch = tonumber(patch),
    }

    local required = version.REQUIRED_NODE_VERSION
    if current.major ~= required.major or current.minor < required.minor then
        return {
            ok = false,
            error = Error(
                "SETUP",
                Error.Types.SETUP.VERSION_MISMATCH,
                string.format("Incompatible mcp-hub version. Found %s, required %s", ver_str, required.string),
                {
                    found = ver_str,
                    required = required.string,
                    install_cmd = string.format("npm install -g mcp-hub@%s", required.string),
                }
            ),
        }
    end

    return {
        ok = true,
    }
end

return M
