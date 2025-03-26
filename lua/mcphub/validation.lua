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
    -- Validate native servers if present
    if opts.native_servers then
        if type(opts.native_servers) ~= "table" then
            return {
                ok = false,
                error = Error("SETUP", Error.Types.SETUP.INVALID_CONFIG, "native_servers must be a table"),
            }
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

--- Validate a property according to requirements
---@param value any The value to validate
---@param prop_type string Type of property (string|function|table)
---@param name string Name of property for error messages
---@param error_type string Error type from Error.Types.NATIVE
---@param object_id? string Optional identifier for error messages
---@param extra_check? function Optional additional validation function
---@return ValidationResult
local function validate_property(value, prop_type, name, error_type, object_id, extra_check)
    if not value or type(value) ~= prop_type then
        return {
            ok = false,
            error = Error("VALIDATION", error_type, string.format("%s must be a %s", name, prop_type)),
        }
    end

    if prop_type == "string" and value == "" then
        return {
            ok = false,
            error = Error("VALIDATION", error_type, string.format("%s cannot be empty", name)),
        }
    end

    if extra_check then
        local ok, err = extra_check(value)
        if not ok then
            return {
                ok = false,
                error = Error(
                    "VALIDATION",
                    error_type,
                    string.format("%s: %s", object_id and string.format("%s in %s", err, object_id) or err, name)
                ),
            }
        end
    end

    return { ok = true }
end

--- Validate a tool definition
---@param tool table Tool definition to validate
---@return ValidationResult
function M.validate_tool(tool)
    -- Validate name
    local name_result = validate_property(tool.name, "string", "Tool name", Error.Types.NATIVE.INVALID_NAME)
    if not name_result.ok then
        return name_result
    end

    -- Validate handler
    local handler_result =
        validate_property(tool.handler, "function", "Handler", Error.Types.NATIVE.INVALID_HANDLER, tool.name)
    if not handler_result.ok then
        return handler_result
    end

    -- Validate inputSchema if present
    if tool.inputSchema then
        local schema_result =
            validate_property(tool.inputSchema, "table", "Input schema", Error.Types.NATIVE.INVALID_SCHEMA, tool.name)
        if not schema_result.ok then
            return schema_result
        end

        -- Check inputSchema structure
        local function validate_schema(schema)
            if schema.type ~= "object" then
                return false, "type must be 'object'"
            end
            if not schema.properties or type(schema.properties) ~= "table" then
                return false, "must have a properties table"
            end
            return true
        end

        local schema_struct = validate_property(
            tool.inputSchema,
            "table",
            "Input schema",
            Error.Types.NATIVE.INVALID_SCHEMA,
            tool.name,
            validate_schema
        )
        if not schema_struct.ok then
            return schema_struct
        end
    end

    return { ok = true }
end

--- Validate a resource definition
---@param resource table Resource definition to validate
---@return ValidationResult
function M.validate_resource(resource)
    local name_result = validate_property(resource.name, "string", "Resource Name", Error.Types.NATIVE.INVALID_NAME)
    if not name_result.ok then
        return name_result
    end
    -- Validate URI
    local uri_result = validate_property(resource.uri, "string", "Resource URI", Error.Types.NATIVE.INVALID_URI)
    if not uri_result.ok then
        return uri_result
    end

    -- Validate handler
    local handler_result =
        validate_property(resource.handler, "function", "Handler", Error.Types.NATIVE.INVALID_HANDLER, resource.uri)
    if not handler_result.ok then
        return handler_result
    end

    return { ok = true }
end

--- Validate a resource template definition
---@param template table Resource template definition to validate
---@return ValidationResult
function M.validate_resource_template(template)
    -- Validate URI template
    local function validate_uri_template(uri)
        if not uri:match("{[^}]+}") then
            return false, "must contain at least one parameter in {param} format"
        end
        return true
    end

    local name_result = validate_property(template.name, "string", "Resource Name", Error.Types.NATIVE.INVALID_NAME)
    if not name_result.ok then
        return name_result
    end
    local uri_result = validate_property(
        template.uriTemplate,
        "string",
        "URI template",
        Error.Types.NATIVE.INVALID_URI,
        nil,
        validate_uri_template
    )
    if not uri_result.ok then
        return uri_result
    end

    -- Validate handler
    local handler_result = validate_property(
        template.handler,
        "function",
        "Handler",
        Error.Types.NATIVE.INVALID_HANDLER,
        template.uriTemplate
    )
    if not handler_result.ok then
        return handler_result
    end

    return { ok = true }
end

--- Validate native server definition
---@param def table Native server definition
---@param server_name string Server name for error messages
---@return ValidationResult
function M.validate_native_server(def)
    local server_name = def.name
    if not def.name then
        return {
            ok = false,
            error = Error("SETUP", Error.Types.SETUP.INVALID_CONFIG, "Native server must contain a name"),
        }
    end
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
    -- Validate tools if present
    if def.capabilities.tools then
        for _, tool in ipairs(def.capabilities.tools) do
            local ok, err = M.validate_tool(tool)
            if not ok then
                return {
                    ok = false,
                    error = err,
                }
            end
        end
    end

    -- Validate resources if present
    if def.capabilities.resources then
        for _, resource in ipairs(def.capabilities.resources) do
            local ok, err = M.validate_resource(resource)
            if not ok then
                return {
                    ok = false,
                    error = err,
                }
            end
        end
    end

    -- Validate resource templates if present
    if def.capabilities.resourceTemplates then
        for _, template in ipairs(def.capabilities.resourceTemplates) do
            local ok, err = M.validate_resource_template(template)
            if not ok then
                return {
                    ok = false,
                    error = err,
                }
            end
        end
    end

    return { ok = true }
end

return M
