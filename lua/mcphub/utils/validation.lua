---@brief [[
--- Validation utilities for MCPHub
--- Handles configuration and input validation
---@brief ]]
local Error = require("mcphub.utils.errors")
local version = require("mcphub.utils.version")

local M = {}

---@class MCPServersConfigFile
---@field mcpServers table<string,MCPServerConfig>
---@field nativeMCPServers table<string,NativeMCPServerConfig>

---@class ValidationResult
---@field ok boolean
---@field error? MCPError

--- Validate setup options
---@param opts MCPHub.Config
---@return ValidationResult
function M.validate_setup_opts(opts)
    if not opts.port then
        return {
            ok = false,
            error = Error("SETUP", Error.Types.SETUP.INVALID_PORT, "Port is required for MCPHub setup"),
        }
    end

    if not opts.config or type(opts.config) ~= "string" then
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
    return { ok = true }
end

--- Validate server configuration
---@param name string Server name to validate
---@param config MCPServerConfig Server configuration
---@return ValidationResult
function M.validate_server_config(name, config)
    if type(config) ~= "table" then
        return {
            ok = false,
            error = Error(
                "VALIDATION",
                Error.Types.SETUP.INVALID_CONFIG,
                string.format("Server '%s' config must be a table", name)
            ),
        }
    end

    local has_stdio = config.command ~= nil
    local has_sse = config.url ~= nil

    -- Check for mixed fields
    if has_stdio and has_sse then
        return {
            ok = false,
            error = Error(
                "VALIDATION",
                Error.Types.SETUP.INVALID_CONFIG,
                string.format("Server '%s' cannot mix stdio and sse fields", name)
            ),
        }
    end

    -- Validate stdio config
    if has_stdio then
        if type(config.command) ~= "string" or config.command == "" then
            return {
                ok = false,
                error = Error(
                    "VALIDATION",
                    Error.Types.SETUP.INVALID_CONFIG,
                    string.format("Server '%s' has invalid or missing command", name)
                ),
            }
        end

        if config.args and not vim.islist(config.args) then
            return {
                ok = false,
                error = Error(
                    "VALIDATION",
                    Error.Types.SETUP.INVALID_CONFIG,
                    string.format("Server '%s' args must be an array", name)
                ),
            }
        end

        if config.env and type(config.env) ~= "table" then
            return {
                ok = false,
                error = Error(
                    "VALIDATION",
                    Error.Types.SETUP.INVALID_CONFIG,
                    string.format("Server '%s' has invalid environment config", name)
                ),
            }
        end

        if config.cwd and (type(config.cwd) ~= "string" or config.cwd == "") then
            return {
                ok = false,
                error = Error(
                    "VALIDATION",
                    Error.Types.SETUP.INVALID_CONFIG,
                    string.format("Server '%s' has invalid cwd: must be a non-empty string", name)
                ),
            }
        end
    elseif has_sse then
        -- Validate SSE config
        if type(config.url) ~= "string" or config.url == "" then
            return {
                ok = false,
                error = Error(
                    "VALIDATION",
                    Error.Types.SETUP.INVALID_CONFIG,
                    string.format("Server '%s' has invalid or missing url", name)
                ),
            }
        end

        -- Try parsing URL
        local ok, err = pcall(function()
            vim.uri_from_fname(config.url)
        end)
        if not ok then
            return {
                ok = false,
                error = Error(
                    "VALIDATION",
                    Error.Types.SETUP.INVALID_CONFIG,
                    string.format("Server '%s' has invalid url format: %s", name, err)
                ),
            }
        end

        if config.headers and type(config.headers) ~= "table" then
            return {
                ok = false,
                error = Error(
                    "VALIDATION",
                    Error.Types.SETUP.INVALID_CONFIG,
                    string.format("Server '%s' has invalid headers config", name)
                ),
            }
        end
    else
        return {
            ok = false,
            error = Error(
                "VALIDATION",
                Error.Types.SETUP.INVALID_CONFIG,
                string.format("Server '%s' must include either command (for stdio) or url (for sse)", name)
            ),
        }
    end

    return { ok = true }
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

---inputSchema will be evaluated if it is a function and is obj is validated
---@param inputSchema table
---@param tool_name string
function M.validate_inputSchema(inputSchema, tool_name)
    if not inputSchema then
        return { ok = true }
    end
    -- Check inputSchema structure
    local function validate_schema(schema)
        if schema.type ~= "object" then
            return false, "type must be 'object'"
        end
        if schema.properties and type(schema.properties) ~= "table" then
            return false, "must have a properties table"
        end
        return true
    end

    return validate_property(
        inputSchema,
        "table",
        "Input schema",
        Error.Types.NATIVE.INVALID_SCHEMA,
        tool_name or "",
        validate_schema
    )
end

--- Validate a tool definition
---@param tool MCPTool Tool definition to validate
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
    return { ok = true }
end

--- Validate a resource definition
---@param resource MCPResource Resource definition to validate
---@return ValidationResult
function M.validate_resource(resource)
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
---@param template MCPResourceTemplate Resource template definition to validate
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

-- Add prompts validation in native server validation
---@param def NativeServerDef Native server definition to validate
---@return {ok: boolean, error: MCPError}
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

    -- Validate prompts if present
    if def.capabilities.prompts then
        for _, prompt in ipairs(def.capabilities.prompts) do
            local ok, err = M.validate_prompt(prompt)
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

--- Validate a prompt definition
---@param prompt MCPPrompt Prompt definition to validate
---@return ValidationResult
function M.validate_prompt(prompt)
    -- Validate name
    local name_result = validate_property(prompt.name, "string", "Prompt name", Error.Types.NATIVE.INVALID_NAME)
    if not name_result.ok then
        return name_result
    end

    -- Validate handler
    local handler_result =
        validate_property(prompt.handler, "function", "Handler", Error.Types.NATIVE.INVALID_HANDLER, prompt.name)
    if not handler_result.ok then
        return handler_result
    end

    return { ok = true }
end

return M
