---@brief [[
--- Validation utilities for MCPHub
--- Handles configuration and input validation
---@brief ]]
local Error = require("mcphub.errors")
local version = require("mcphub.version")

local M = {}

--- Validate native server definition
---@param def table Native server definition
---@param server_name string Server name for error messages
---@return ValidationResult
local function validate_native_server(def, server_name)
    if not def.capabilities then
        return {
            ok = false,
            error = Error(
                "SETUP",
                Error.Types.SETUP.INVALID_CONFIG,
                string.format("Native server '%s' must contain capabilities", server_name)
            ),
        }
    end

    -- Validate capabilities
    if def.capabilities.tools and type(def.capabilities.tools) ~= "table" then
        return {
            ok = false,
            error = Error(
                "SETUP",
                Error.Types.SETUP.INVALID_CONFIG,
                string.format("tools must be an array in native server '%s'", server_name)
            ),
        }
    end

    -- Validate tools if present
    if def.capabilities.tools then
        for _, tool in ipairs(def.capabilities.tools) do
            if not tool.name or not tool.handler or type(tool.handler) ~= "function" then
                return {
                    ok = false,
                    error = Error(
                        "SETUP",
                        Error.Types.SETUP.INVALID_CONFIG,
                        string.format("Each tool must have name and handler in native server '%s'", server_name)
                    ),
                }
            end
        end
    end

    return { ok = true }
end

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
    -- Validate native servers if present
    if opts.native_servers then
        if type(opts.native_servers) ~= "table" then
            return {
                ok = false,
                error = Error("SETUP", Error.Types.SETUP.INVALID_CONFIG, "native_servers must be a table"),
            }
        end

        for name, def in pairs(opts.native_servers) do
            local result = validate_native_server(def, name)
            if not result.ok then
                return result
            end
        end
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
    local file = io.open(path, "r")
    if not file then
        return {
            ok = false,
            error = Error("SETUP", Error.Types.SETUP.INVALID_CONFIG, string.format("Config file not found: %s", path)),
        }
    end

    local content = file:read("*a")
    file:close()

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

    -- Validate native servers section if present
    if json.nativeMCPServers then
        if type(json.nativeMCPServers) ~= "table" then
            return {
                ok = false,
                content = content,
                error = Error(
                    "SETUP",
                    Error.Types.SETUP.INVALID_CONFIG,
                    "Config file's nativeMCPServers must be an object"
                ),
            }
        end

        -- Validate each native server's config
        for server_name, server_config in pairs(json.nativeMCPServers) do
            -- Validate disabled_tools if present
            if server_config.disabled_tools ~= nil then
                if type(server_config.disabled_tools) ~= "table" then
                    return {
                        ok = false,
                        content = content,
                        error = Error(
                            "SETUP",
                            Error.Types.SETUP.INVALID_CONFIG,
                            string.format("disabled_tools must be an array in native server %s", server_name)
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
                                string.format(
                                    "disabled_tools must contain non-empty strings in native server %s",
                                    server_name
                                )
                            ),
                        }
                    end
                end
            end

            -- Validate custom_instructions if present
            if
                server_config.custom_instructions ~= nil
                and not validate_custom_instructions(server_config.custom_instructions)
            then
                return {
                    ok = false,
                    content = content,
                    error = Error(
                        "SETUP",
                        Error.Types.SETUP.INVALID_CONFIG,
                        string.format("Invalid custom_instructions format in native server %s", server_name)
                    ),
                }
            end
        end
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
