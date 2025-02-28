---@brief [[
--- Utility functions for Servers view
---@brief ]]
local Text = require("mcphub.utils.text")
local NuiLine = require("mcphub.utils.nuiline")
local highlights = require("mcphub.utils.highlights")

local M = {}

-- Parameter type handlers for validation and conversion
local type_handlers = {
    string = {
        validate = function(value)
            return true
        end,
        convert = function(value)
            return value
        end,
        format = function()
            return "string"
        end
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
        end
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
        end
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
        end
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
                local item_validator = type_handlers[schema.items.type].validate
                for _, item in ipairs(arr) do
                    if not item_validator(item) then
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
                    return string.format("[%s]", table.concat(vim.tbl_map(function(v)
                        return string.format("%q", v)
                    end, schema.items.enum), ", "))
                elseif schema.items.type then
                    return string.format("%s[]", type_handlers[schema.items.type].format())
                end
            end
            return "array"
        end
    }
}

--- Validate a single parameter value
---@param value string The value to validate
---@param param_schema table Parameter schema
---@return boolean is_valid, string|nil error_message
function M.validate_param(value, param_schema)
    if not param_schema or not param_schema.type then
        return false, "Invalid parameter schema"
    end

    local handler = type_handlers[param_schema.type]
    if not handler then
        return false, "Unknown parameter type: " .. param_schema.type
    end

    local is_valid = handler.validate(value, param_schema)
    if not is_valid then
        return false, string.format("Invalid %s value: %s", param_schema.type, value)
    end

    return true, nil
end

--- Convert validated string input to proper type
---@param value string The string value to convert
---@param param_schema table Parameter schema
---@return any Converted value
function M.convert_param(value, param_schema)
    local handler = type_handlers[param_schema.type]
    return handler.convert(value)
end

--- Format parameter type for display
---@param param_schema table Parameter schema
---@return string Formatted type string
function M.format_param_type(param_schema)
    local handler = type_handlers[param_schema.type]
    if not handler then
        return param_schema.type
    end
    return handler.format(param_schema)
end

-- Section rendering utilities
function M.render_section_start(title, highlight)
    local lines = {}
    table.insert(lines, NuiLine():append("╭─ ", Text.highlights.muted)
        :append(" " .. title .. " ", highlight or Text.highlights.header))
    return lines
end

function M.render_section_content(content, indent_level)
    local lines = {}
    local padding = string.rep(" ", indent_level or 1)
    for _, line in ipairs(content) do
        local rendered_line = NuiLine()
        if type(line) == "string" then
            rendered_line:append("│", Text.highlights.muted):append(padding, Text.highlights.muted):append(line)
        else
            rendered_line:append("│", Text.highlights.muted):append(padding, Text.highlights.muted):append(line)
        end
        table.insert(lines, Text.pad_line(rendered_line))
    end
    return lines
end

function M.render_section_end()
    return vim.tbl_map(Text.pad_line,
        {NuiLine():append("╰─", Text.highlights.muted):append(" ", Text.highlights.muted)})
end

--- Format duration in seconds to human readable string
---@param seconds number Duration in seconds
---@return string Formatted duration
function M.format_uptime(seconds)
    if seconds < 60 then
        return string.format("%ds", seconds)
    elseif seconds < 3600 then
        return string.format("%dm %ds", math.floor(seconds / 60), seconds % 60)
    else
        local hours = math.floor(seconds / 3600)
        local mins = math.floor((seconds % 3600) / 60)
        return string.format("%dh %dm", hours, mins)
    end
end

--- Get ordered list of parameters from schema
---@param tool_info table Tool information with schema
---@param current_values table<string, string> Current parameter values
---@return table[] List of parameter objects
function M.get_ordered_params(tool_info, current_values)
    if not tool_info or not tool_info.inputSchema or not tool_info.inputSchema.properties then
        return {}
    end

    local params = {}
    for name, prop in pairs(tool_info.inputSchema.properties) do
        table.insert(params, {
            name = name,
            type = prop.type,
            description = prop.description,
            required = vim.tbl_contains(tool_info.inputSchema.required or {}, name),
            default = prop.default,
            value = current_values[name]
        })
    end

    -- Sort by required first, then name
    table.sort(params, function(a, b)
        if a.required ~= b.required then
            return a.required
        end
        return a.name < b.name
    end)

    return params
end

--- Validate all required parameters are filled
---@param tool_info table Tool information with schema
---@param values table<string, string> Current parameter values
---@return boolean, string|nil is_valid, error_message
function M.validate_all_params(tool_info, values)
    if not tool_info or not tool_info.inputSchema then
        return false, "No parameters to validate"
    end

    local errors = {}
    local params = M.get_ordered_params(tool_info, values)

    for _, param in ipairs(params) do
        if param.required and (not values[param.name] or values[param.name] == "") then
            errors[param.name] = "Required parameter"
        end
    end

    if next(errors) then
        return false, "Some required parameters are missing", errors
    end

    return true, nil, {}
end

--- Render server information
---@param server table Server data
---@param line_offset number Current line number offset
---@return NuiLine[] lines, number new_offset
function M.render_server(server, line_offset)
    local lines = {}

    local current_line = line_offset + 1
    -- Server header
    local title = NuiLine():append("╭─ ", Text.highlights.muted):append(" " .. server.name .. " ",
        Text.highlights.header_btn)
    table.insert(lines, Text.pad_line(title))

    -- Server details
    if server.uptime then
        local uptime = NuiLine():append("│ ", Text.highlights.muted):append("Uptime: ", Text.highlights.muted):append(
            M.format_uptime(server.uptime), Text.highlights.info)
        table.insert(lines, Text.pad_line(uptime))
    end

    -- Capabilities
    if server.capabilities then
        -- Tools
        if #server.capabilities.tools > 0 then
            table.insert(lines, Text.pad_line(NuiLine():append("│", Text.highlights.muted)))
            table.insert(lines, Text.pad_line(
                NuiLine():append("│ ", Text.highlights.muted):append(" Tools: ", Text.highlights.header)))

            for _, tool in ipairs(server.capabilities.tools) do
                -- Tool name
                local tool_line = NuiLine():append("│  • ", Text.highlights.muted):append(tool.name,
                    Text.highlights.success)
                table.insert(lines, Text.pad_line(tool_line))

                -- Track tool line number at the actual buffer position
                tool._line_nr = line_offset + #lines

                -- Tool description
                if tool.description then
                    for _, desc_line in ipairs(Text.multiline(tool.description, highlights.groups.muted)) do
                        local desc = NuiLine():append("│    ", Text.highlights.muted):append(desc_line,
                            Text.highlights.muted)
                        table.insert(lines, Text.pad_line(desc))
                    end
                end
            end
        end

        -- Resources
        if #server.capabilities.resources > 0 then
            table.insert(lines, Text.pad_line(NuiLine():append("│", Text.highlights.muted)))
            table.insert(lines, Text.pad_line(
                NuiLine():append("│ ", Text.highlights.muted):append(" Resources: ", Text.highlights.header)))
            for _, resource in ipairs(server.capabilities.resources) do
                local res_line = NuiLine():append("│  • ", Text.highlights.muted):append(resource.name,
                    Text.highlights.success):append(" (", Text.highlights.muted):append(resource.mimeType,
                    Text.highlights.info):append(")", Text.highlights.muted)
                table.insert(lines, Text.pad_line(res_line))
            end
        end
    end

    -- Server footer
    table.insert(lines, Text.pad_line(NuiLine():append("╰─", Text.highlights.muted)))
    table.insert(lines, Text.empty_line())

    return lines, line_offset + #lines
end

--- Render parameter input form
---@param tool_info table Tool information with schema
---@param state table Current parameter state (values, errors, etc)
---@return NuiLine[] lines, table<number, string> param_lines, number submit_line
function M.render_params_form(tool_info, state)
    local lines = {}
    local param_lines = {}
    local submit_line_num = nil

    -- Start params section
    vim.list_extend(lines, vim.tbl_map(Text.pad_line, M.render_section_start("Input Parameters")))

    -- Parameters
    local params = M.get_ordered_params(tool_info, state.values or {})

    if #params == 0 then
        -- Show no parameters message inline with submit button
        local content = NuiLine():append("No parameters required ", Text.highlights.muted)
        local submit_content = {}
        if state.is_executing then
            submit_content = {NuiLine():append("[ ", Text.highlights.muted):append("Processing...",
                Text.highlights.muted):append(" ]", Text.highlights.muted)}
        else
            submit_content = {NuiLine():append("[ ", Text.highlights.success_fill):append("Submit",
                Text.highlights.success_fill):append(" ]", Text.highlights.success_fill)}
        end
        vim.list_extend(lines, M.render_section_content({content, Text.empty_line()}, 2))
        vim.list_extend(lines, M.render_section_content(submit_content, 2))
        submit_line_num = #lines
    else
        for _, param in ipairs(params) do
            -- Parameter name line with type
            local name_line = NuiLine():append(param.required and "* " or "  ", Text.highlights.error):append(
                param.name, Text.highlights.success):append(" (", Text.highlights.muted):append(M.format_param_type(
                param), Text.highlights.muted):append(")", Text.highlights.muted)
            vim.list_extend(lines, M.render_section_content({name_line}, 2))

            -- Description if any
            if param.description then
                for _, desc_line in ipairs(Text.multiline(param.description, Text.highlights.muted)) do
                    vim.list_extend(lines, M.render_section_content({desc_line}, 4))
                end
            end

            -- Value input
            local value = (state.values or {})[param.name]
            local input_line = NuiLine():append("> ", Text.highlights.success):append(value or "", Text.highlights.info)
            vim.list_extend(lines, M.render_section_content({input_line}, 2))
            param_lines[#lines] = param.name

            -- Error if any
            if state.errors and state.errors[param.name] then
                local error_line = NuiLine():append("⚠ ", Text.highlights.error):append(state.errors[param.name],
                    Text.highlights.error)
                vim.list_extend(lines, M.render_section_content({error_line}, 2))
            end

            table.insert(lines, Text.pad_line(NuiLine():append("│", Text.highlights.muted)))
        end

        -- Submit button for when we have parameters
        local submit_content = {}
        if state.is_executing then
            submit_content = {NuiLine():append("[ ", Text.highlights.muted):append("Processing...",
                Text.highlights.muted):append(" ]", Text.highlights.muted)}
        else
            submit_content = {NuiLine():append("[ ", Text.highlights.success_fill):append("Submit",
                Text.highlights.success_fill):append(" ]", Text.highlights.success_fill)}
        end
        vim.list_extend(lines, M.render_section_content(submit_content, 2))
        submit_line_num = #lines
    end

    -- Submit error
    if state.submit_error then
        local error_line = NuiLine():append("⚠ ", Text.highlights.error):append(state.submit_error,
            Text.highlights.error)
        vim.list_extend(lines, M.render_section_content({error_line}, 2))
    end

    -- End params section
    vim.list_extend(lines, M.render_section_end())

    -- Result section if present
    if state.result then
        table.insert(lines, Text.pad_line(NuiLine())) -- Empty line between sections
        vim.list_extend(lines, vim.tbl_map(Text.pad_line, M.render_section_start("Result")))

        local result_json = state.result
        if type(result_json) == "table" then
            result_json = vim.fn.json_encode(result_json)
        end

        for _, line in ipairs(Text.multiline(result_json, Text.highlights.info)) do
            vim.list_extend(lines, M.render_section_content({line}, 1))
        end

        vim.list_extend(lines, M.render_section_end())
    end

    return lines, param_lines, submit_line_num
end

return M
