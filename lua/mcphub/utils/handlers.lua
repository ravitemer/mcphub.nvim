local Error = require("mcphub.utils.errors")
local State = require("mcphub.state")
local log = require("mcphub.utils.log")

local M = {}

-- Parameter type handlers for validation and conversion
M.TypeHandlers = {
    string = {
        validate = function(value)
            return true
        end,
        convert = function(value)
            return tostring(value)
        end,
        format = function()
            return "string"
        end,
    },
    number = {
        validate = function(value)
            return tonumber(value) ~= nil
        end,
        convert = function(value)
            return tonumber(value)
        end,
        format = function()
            return "number"
        end,
    },
    integer = {
        validate = function(value)
            local num = tonumber(value)
            return num and math.floor(num) == num
        end,
        convert = function(value)
            return math.floor(tonumber(value))
        end,
        format = function()
            return "integer"
        end,
    },
    boolean = {
        validate = function(value)
            return value == "true" or value == "false"
        end,
        convert = function(value)
            return value == "true"
        end,
        format = function()
            return "boolean"
        end,
    },
    object = {
        validate = function(value, schema)
            -- Parse JSON object string and validate each property
            -- FIXME: need to implement proper validation for objects
            local ok, obj = pcall(vim.fn.json_decode, value)
            if not ok or type(obj) ~= "table" then
                return false
            end
            return true
        end,
        format = function(schema)
            if schema.properties then
                local props = {}
                for k, v in pairs(schema.properties) do
                    table.insert(props, string.format("%s: %s", k, M.TypeHandlers[v.type].format(v)))
                end
                return string.format("{%s}", table.concat(props, ", "))
            end
            return "object"
        end,
    },
    array = {
        validate = function(value, schema)
            -- Parse JSON array string and validate each item
            local ok, arr = pcall(vim.fn.json_decode, value)
            if not ok or type(arr) ~= "table" then
                return false
            end
            -- If items has enum, validate against allowed values
            if schema.items and schema.items.enum then
                for _, item in ipairs(arr) do
                    if not vim.tbl_contains(schema.items.enum, item) then
                        return false
                    end
                end
            end
            -- If items has type, validate each item's type
            if schema.items and schema.items.type then
                local item_validator = M.TypeHandlers[schema.items.type].validate
                for _, item in ipairs(arr) do
                    if not item_validator(item, schema.items) then
                        return false
                    end
                end
            end
            return true
        end,
        convert = function(value)
            return vim.fn.json_decode(value)
        end,
        format = function(schema)
            if schema.items then
                if schema.items.enum then
                    return string.format(
                        "[%s]",
                        table.concat(
                            vim.tbl_map(function(v)
                                return string.format("%q", v)
                            end, schema.items.enum),
                            ", "
                        )
                    )
                elseif schema.items.type then
                    return string.format("%s[]", M.TypeHandlers[schema.items.type].format(schema.items))
                end
            end
            return "array"
        end,
    },
}

-- Process handlers for server process
M.ProcessHandlers = {
    --- Handle server process output
    --- @param data string Raw output data
    --- @param hub MCPHub The hub instance
    --- @param opts table Options including callbacks
    --- @return boolean handled Whether the data was handled
    handle_output = function(data, hub, opts)
        if not data then
            return ""
        end

        -- Try to parse as JSON
        local ok, parsed = pcall(vim.json.decode, data)
        if not ok then
            -- Not JSON, treat as raw log
            State:add_server_output({
                type = "info", -- Default to info for non-JSON messages
                message = data,
                timestamp = vim.loop.now(), -- Use system time if no timestamp
                data = nil,
            })
            return data
        end

        -- Handle structured server logs
        if parsed.type then
            -- Use message timestamp if valid ISO string, otherwise system time
            local timestamp = vim.loop.now()
            if parsed.timestamp then
                -- Try to convert ISO string to unix timestamp
                local success, ts = pcall(function()
                    return vim.fn.strptime("%Y-%m-%dT%H:%M:%S", parsed.timestamp)
                end)
                if success then
                    timestamp = ts
                end
            end

            State:add_server_output({
                type = parsed.type, -- warn/error/info/debug
                message = parsed.message,
                code = parsed.code,
                timestamp = timestamp,
                data = parsed.data,
            })

            -- Special error handling
            if parsed.type == "error" then
                local error_obj =
                    Error("SERVER", parsed.code or Error.Types.SERVER.CONNECTION, parsed.message, parsed.data)
                State:add_error(error_obj)
                -- log.error(tostring(error_obj))
                hub:handle_server_error(tostring(error_obj), opts)
                return true
            end

            -- Log at appropriate level
            log[parsed.type]({
                code = parsed.code or "SERVER_" .. string.upper(parsed.type),
                message = parsed.message,
                data = parsed.data,
            })

            -- Handle ready state (backward compatibility)
            if
                parsed.type == "info"
                and parsed.message == "MCP_HUB_STARTED"
                and parsed.data
                and parsed.data.status == "ready"
            then
                hub:handle_server_ready(opts)
                return true
            end

            --Handle hub updates "MCP_HUB_UPDATED"
            --

            -- Handle tool/resourcelist updates
            if
                parsed.type == "info" and (parsed.code == "TOOL_LIST_CHANGED" or parsed.code == "RESOURCE_LIST_CHANGED")
            then
                hub:handle_capability_updates(parsed.data)
                return true
            end
        end

        return true
    end,
}

--- API response handlers
M.ResponseHandlers = {
    --- Process API errors and create structured error objects
    --- @param error table|string Error from API
    --- @param context table Additional context to include
    --- @return MCPError Structured error object
    process_error = function(error, context)
        if type(error) == "table" then
            if error.code and error.message then
                -- Already structured error
                if context then
                    error.data = vim.tbl_extend("force", error.data or {}, context)
                end
                return Error("SERVER", Error.Types.SERVER.API_ERROR, vim.inspect(error), context)
            end
            -- Table error without proper structure
            return Error("SERVER", Error.Types.SERVER.API_ERROR, vim.inspect(error), context)
        end
        -- String error
        return Error("SERVER", Error.Types.SERVER.API_ERROR, error, context)
    end,

    --- Handle curl specific errors
    --- @param response table Curl response
    --- @param context table Request context
    --- @return MCPError|nil error Structured error if any
    handle_curl_error = function(response, context)
        if not response then
            return Error("SERVER", Error.Types.SERVER.CURL_ERROR, "No response from server", context)
        end

        if response.exit ~= 0 then
            local error_code = ({
                [7] = Error.Types.SERVER.CONNECTION,
                [28] = Error.Types.SERVER.TIMEOUT,
            })[response.exit] or Error.Types.SERVER.CURL_ERROR

            local error_msg = ({
                [7] = "Connection refused - Server not running",
                [28] = "Request timed out",
            })[response.exit] or string.format("Request failed (code %d)", response.exit or 0)

            return Error(
                "SERVER",
                error_code,
                error_msg,
                vim.tbl_extend("force", context, {
                    exit_code = response.exit,
                })
            )
        end

        return nil
    end,

    --- Handle HTTP error responses
    --- @param response table HTTP response
    --- @param context table Request context
    --- @return MCPError|nil error Structured error if any
    handle_http_error = function(response, context)
        if response.status < 400 then
            return nil
        end

        local ok, parsed_error = pcall(vim.fn.json_decode, response.body)
        if ok and parsed_error.error then
            return Error(
                "SERVER",
                parsed_error.code or Error.Types.SERVER.API_ERROR,
                parsed_error.error,
                parsed_error.data or {}
            )
        end

        return Error(
            "SERVER",
            Error.Types.SERVER.API_ERROR,
            string.format("Server error (%d)", response.status),
            vim.tbl_extend("force", context, {
                status = response.status,
                body = response.body,
            })
        )
    end,

    --- Parse JSON response
    --- @param response string Raw response body
    --- @param context table Request context
    --- @return table|nil result Parsed response or nil
    --- @return MCPError|nil error Structured error if any
    parse_json = function(response, context)
        if not response then
            return nil, Error("SERVER", Error.Types.SERVER.API_ERROR, "Empty response from server", context)
        end

        local ok, decoded = pcall(vim.fn.json_decode, response)
        if not ok then
            return nil,
                Error(
                    "SERVER",
                    Error.Types.SERVER.API_ERROR,
                    "Invalid response: Not JSON",
                    vim.tbl_extend("force", context, {
                        body = response,
                    })
                )
        end

        return decoded, nil
    end,
}

return M
