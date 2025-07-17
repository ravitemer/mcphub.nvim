local Error = require("mcphub.utils.errors")
local State = require("mcphub.state")
local constants = require("mcphub.utils.constants")
local log = require("mcphub.utils.log")

local M = {}

local function format_config_changes(changes)
    local removed = changes.removed or {}
    local added = changes.added or {}
    local modified = changes.modified or {}
    local msg = ""
    if #added > 0 then
        msg = msg .. "Added:\n"
        for _, item in ipairs(added) do
            msg = msg .. string.format("  - %s\n", item)
        end
    end
    if #modified > 0 then
        msg = msg .. "Modified:\n"
        for _, item in ipairs(modified) do
            msg = msg .. string.format("  - %s\n", item)
        end
    end
    if #removed > 0 then
        msg = msg .. "Removed:\n"
        for _, item in ipairs(removed) do
            msg = msg .. string.format("  - %s\n", item)
        end
    end
    return msg
end

-- SSE Event handlers
M.SSEHandlers = {
    ---@param event string Event type
    ---@param data table Event data
    ---@param hub MCPHub.Hub Hub instance
    handle_sse_event = function(event, data, hub)
        local is_ui_shown = State.ui_instance and State.ui_instance.is_shown or false
        if event == constants.EventTypes.HEARTBEAT then
            log.trace("Heartbeat event received")
        else
            log.debug(
                string.format(
                    "Event: %s %s ",
                    event,
                    (data.type or data.state) and ": " .. (data.type or data.state) or ""
                )
            )
        end
        if event == constants.EventTypes.HUB_STATE then
            local state = data.state
            if state then
                State:update_hub_state(state)
            end
            if state == constants.HubState.ERROR then
                hub:handle_hub_stopped("Hub entered error state: " .. (data.message or "unknown error"))
            elseif state == constants.HubState.STOPPING then
                hub:handle_hub_stopping()
            elseif state == constants.HubState.STOPPED then
                hub:handle_hub_stopped("Hub stopped")
            elseif state == constants.HubState.RESTARTING then
                hub:handle_hub_restarting()
            elseif state == constants.HubState.READY or state == constants.HubState.RESTARTED then
                hub:handle_hub_ready()
            end
        elseif event == constants.EventTypes.SUBSCRIPTION_EVENT then
            local is_capability_type = vim.tbl_contains({
                constants.SubscriptionTypes.TOOL_LIST_CHANGED,
                constants.SubscriptionTypes.RESOURCE_LIST_CHANGED,
                constants.SubscriptionTypes.PROMPT_LIST_CHANGED,
            }, data.type)
            if is_capability_type then
                hub:handle_capability_updates(data)
            elseif data.type == constants.SubscriptionTypes.CONFIG_CHANGED then
                -- if not is_ui_shown then
                --     local has_significant_changes = data.isSignificant == true
                --     if not has_significant_changes then
                --         vim.notify("MCP Hub Config Changed: No Significant changes found", vim.log.levels.INFO, {
                --             title = "MCP Hub",
                --         })
                --     end
                -- end
                hub:reload_config()
            elseif data.type == constants.SubscriptionTypes.SERVERS_UPDATING then
                if not is_ui_shown then
                    vim.notify("MCP Hub Config Changed", vim.log.levels.INFO)
                end
                hub:refresh()
            elseif data.type == constants.SubscriptionTypes.SERVERS_UPDATED then
                if not is_ui_shown then
                    vim.notify(
                        "MCP Servers Updated:\n\n" .. format_config_changes(data.changes or {}),
                        vim.log.levels.INFO
                    )
                end
                hub:refresh()
            elseif data.type == constants.SubscriptionTypes.WORKSPACES_UPDATED then
                hub:refresh()
            end
        elseif event == constants.EventTypes.LOG then
            -- Use message timestamp if valid ISO string, otherwise system time
            local timestamp = vim.loop.now()
            if data.timestamp then
                -- Try to convert ISO string to unix timestamp
                local success, ts = pcall(function()
                    return vim.fn.strptime("%Y-%m-%dT%H:%M:%S", data.timestamp)
                end)
                if success then
                    timestamp = ts
                end
            end
            State:add_server_output({
                type = data.type,
                message = data.message,
                code = data.code,
                timestamp = timestamp,
                data = data.data,
            })
            -- Handle errors specially
            if data.type == "error" then
                local error_obj = Error("SERVER", data.code or Error.Types.SERVER.CONNECTION, data.message, data.data)
                State:add_error(error_obj)
            end
        end
    end,
}

-- Parameter type handlers for validation and conversion
M.TypeHandlers = {
    string = {
        validate = function(value)
            return type(value) == "string"
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
            return math.floor(tonumber(value) and tonumber(value) or 0)
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
                    if v.type then
                        local type_handler = M.TypeHandlers[v.type]
                        table.insert(
                            props,
                            string.format("%s: %s", k, type_handler and type_handler.format(v) or v.type)
                        )
                    elseif v.anyOf then
                        table.insert(
                            props,
                            string.format(
                                "%s: anyOf(%s)",
                                k,
                                vim.iter(v.anyOf)
                                    :map(function(item)
                                        return vim.inspect(item.type or "unknown")
                                    end)
                                    :join(",")
                            )
                        )
                    else
                        table.insert(props, string.format("%s: %s", k, "unknown"))
                    end
                end
                return string.format("{%s}", table.concat(props, ", "))
            end
            return "object"
        end,
        convert = function(value)
            return vim.fn.json_decode(value)
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

--- API response handlers
M.ResponseHandlers = {
    --- Process API errors and create structured error objects
    --- @param error table|string Error from API
    --- @param context? table Additional context to include
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

        local ok, decoded = pcall(
            vim.json.decode,
            response,
            { luanil = {
                object = true,
                array = true,
            } }
        )
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
