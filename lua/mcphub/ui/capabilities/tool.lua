local Base = require("mcphub.ui.capabilities.base")
local NuiLine = require("mcphub.utils.nuiline")
local State = require("mcphub.state")
local Text = require("mcphub.utils.text")
local highlights = require("mcphub.utils.highlights").groups
local Handlers = require("mcphub.utils.handlers")
local log = require("mcphub.utils.log")
local validation = require("mcphub.utils.validation")

---@class ToolHandler : CapabilityHandler
---@field super CapabilityHandler
local ToolHandler = setmetatable({}, {
    __index = Base,
})
ToolHandler.__index = ToolHandler
ToolHandler.type = "tool"
ToolHandler.parsedInputSchema = {}

function ToolHandler:new(server_name, capability_info, view)
    local self = Base:new(server_name, capability_info, view)
    setmetatable(self, ToolHandler)
    self.state = vim.tbl_extend("force", self.state, {
        params = {
            values = {},
            errors = {},
        },
    })
    return self
end

-- Parameter ordering
function ToolHandler:get_ordered_params(inputSchema)
    if not inputSchema or not inputSchema.properties then
        return {}
    end

    local params = {}
    for name, prop in pairs(inputSchema.properties) do
        table.insert(params, {
            name = name,
            type = prop.type,
            description = prop.description,
            required = vim.tbl_contains(inputSchema.required or {}, name),
            default = prop.default,
            value = self.state.params.values[name],
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

-- Parameter handling
function ToolHandler:validate_param(name, value)
    local param_schema = self.parsedInputSchema.properties[name]
    if not param_schema or not param_schema.type then
        return false, "Invalid parameter schema"
    end

    -- Get type handler
    local handler = Handlers.TypeHandlers[param_schema.type]
    if not handler then
        return false, "Unknown parameter type: " .. param_schema.type
    end

    -- Validate value
    local is_valid = handler.validate(value, param_schema)
    if not is_valid then
        return false, string.format("Invalid %s value: %s", param_schema.type, value)
    end

    return true, nil
end

function ToolHandler:convert_param(name, value)
    local param_schema = self.parsedInputSchema.properties[name]
    local handler = Handlers.TypeHandlers[param_schema.type]
    if not handler then
        return value
    end
    return handler.convert(value)
end

function ToolHandler:format_param_type(param)
    local handler = Handlers.TypeHandlers[param.type]
    if not handler then
        return param.type
    end
    return handler.format(param)
end

function ToolHandler:validate_all_params()
    if not self.parsedInputSchema then
        return true, nil, {}
    end

    local errors = {}
    local params = self:get_ordered_params(self.parsedInputSchema)

    for _, param in ipairs(params) do
        local value = self.state.params.values[param.name]

        -- Check required fields
        if param.required and (not value or value == "") then
            errors[param.name] = "Required parameter"
        -- Only validate non-empty values
        elseif value and value ~= "" then
            local ok, err = self:validate_param(param.name, value)
            if not ok then
                errors[param.name] = err
            end
        end
        -- Skip validation for empty optional fields
    end

    if next(errors) then
        return false, "Some required parameters are missing or invalid", errors
    end

    return true, nil, {}
end

-- Action handling
-- Common callback logic for input handling
function ToolHandler:handle_param_update(param_name, input)
    -- Clear previous error
    self.state.params.errors[param_name] = nil

    -- Handle empty input
    if input == "" then
        -- Check if field is required
        local is_required = vim.tbl_contains(self.parsedInputSchema.required or {}, param_name)
        if is_required then
            self.state.params.errors[param_name] = "Required parameter"
        else
            -- For optional fields, clear value and error
            self.state.params.values[param_name] = nil
        end
    else
        -- Only validate non-empty input
        local ok, err = self:validate_param(param_name, input)
        if not ok then
            self.state.params.errors[param_name] = err
        else
            -- Update value
            self.state.params.values[param_name] = input
        end
    end
    self.view:draw()
end

function ToolHandler:handle_input_action(param_name)
    local param_schema = self.parsedInputSchema.properties[param_name]
    if not param_schema then
        return
    end

    self:handle_input(
        string.format("%s (%s): ", param_name, self:format_param_type(param_schema)),
        self.state.params.values[param_name],
        function(input)
            self:handle_param_update(param_name, input)
        end
    )
end

function ToolHandler:handle_text_box(line)
    local type, context = self:get_line_info(line)
    if type == "input" then
        local param_name = context
        local param_schema = self.parsedInputSchema.properties[param_name]
        if not param_schema then
            return
        end

        self:open_text_box(
            string.format("%s (%s)", param_name, self:format_param_type(param_schema)),
            self.state.params.values[param_name] or "",
            function(input)
                self:handle_param_update(param_name, input)
            end
        )
    end
end

function ToolHandler:handle_action(line)
    local type, context = self:get_line_info(line)
    if not type then
        return
    end

    if type == "input" then
        self:handle_input_action(context)
    elseif type == "submit" then
        self:execute()
    end
end

-- Execution
function ToolHandler:execute()
    -- Check if already executing
    if self.state.is_executing then
        vim.notify("Tool is already running", vim.log.levels.WARN)
        return
    end

    -- Validate all parameters first
    local ok, err, errors = self:validate_all_params()
    self.state.params.errors = errors
    self.state.error = err
    if not ok then
        self.view:draw()
        return
    end

    -- Set executing state
    self.state.is_executing = true
    self.state.error = nil
    self.view:draw()

    -- Convert all parameters to their proper types
    local converted_values = {}
    for name, value in pairs(self.state.params.values) do
        converted_values[name] = self:convert_param(name, value)
    end

    log.debug(string.format("Executing tool %s with parameters: %s", self.def.name, vim.inspect(converted_values)))
    -- Execute tool
    if State.hub_instance then
        State.hub_instance:call_tool(self.server_name, self.def.name, converted_values, {
            caller = {
                type = "hubui",
                hubui = State.ui_instance,
            },
            parse_response = true,
            callback = function(response, err)
                self:handle_response(response, err)
                self.view:draw()
            end,
        })
    end
end

function ToolHandler:render_submit()
    local submit_content
    if self.state.is_executing then
        submit_content = NuiLine():append("[ " .. Text.icons.event .. " Processing... ]", highlights.muted)
    else
        submit_content = NuiLine():append("[ " .. Text.icons.gear .. " Submit ]", highlights.success_fill)
    end
    return submit_content
end

-- Rendering
function ToolHandler:render_param_form(line_offset)
    -- Clear previous line tracking
    self:clear_line_tracking()

    local lines = {}

    local inputSchema = self.def.inputSchema
    local is_function = type(inputSchema) == "function"
    -- Parameters section
    vim.list_extend(
        lines,
        self:render_section_start((is_function and "(" .. Text.icons.event .. " Dynamic) " or "") .. "Input Params")
    )
    inputSchema = self:get_inputSchema(inputSchema)
    self.parsedInputSchema = inputSchema
    if not inputSchema or not next(inputSchema.properties or {}) then
        -- No parameters case
        local placeholder = NuiLine():append("No parameters required ", highlights.muted)

        -- Submit button
        local submit_content = self:render_submit()
        vim.list_extend(
            lines,
            self:render_section_content({ placeholder, NuiLine():append(" ", highlights.muted), submit_content }, 2)
        )

        -- Track submit line
        self:track_line(line_offset + #lines, "submit")
    else
        -- Render each parameter
        local params = self:get_ordered_params(inputSchema)
        for _, param in ipairs(params) do
            -- Parameter name and type
            local name_line = NuiLine()
                :append(param.required and "* " or "  ", highlights.error)
                :append(param.name, highlights.success)
                :append(string.format(" (%s)", self:format_param_type(param)), highlights.muted)
            vim.list_extend(lines, self:render_section_content({ name_line }, 2))

            -- Description if any
            if param.description then
                for _, desc_line in ipairs(Text.multiline(param.description, highlights.muted)) do
                    vim.list_extend(lines, self:render_section_content({ desc_line }, 4))
                end
            end

            -- Input field
            local value = self.state.params.values[param.name]
            local input_line = NuiLine():append("> ", highlights.success):append(value or "", highlights.info)
            vim.list_extend(lines, self:render_section_content({ input_line }, 2))

            -- Track input line
            self:track_line(line_offset + #lines, "input", param.name)

            -- Error if any
            if self.state.params.errors[param.name] then
                local error_lines = Text.multiline(self.state.params.errors[param.name], highlights.error)
                vim.list_extend(lines, self:render_section_content(error_lines, 2))
            end

            table.insert(lines, Text.pad_line(NuiLine():append("│", highlights.muted)))
        end

        -- Submit button
        local submit_content = self:render_submit()
        vim.list_extend(lines, self:render_section_content({ submit_content }, 2))

        -- Track submit line
        self:track_line(line_offset + #lines, "submit")
    end

    -- Error message
    if self.state.error then
        local error_lines = Text.multiline(self.state.error, highlights.error)
        vim.list_extend(lines, self:render_section_content(error_lines, 2))
    end
    vim.list_extend(lines, self:render_section_end())
    return lines
end

function ToolHandler:get_inputSchema(inputSchema)
    local base = {
        type = "object",
        properties = {},
    }
    inputSchema = self.def.inputSchema
    if not inputSchema or (type(inputSchema) ~= "function" and not next(inputSchema or {})) then
        inputSchema = base
    end
    local parsedSchema = inputSchema
    if type(inputSchema) == "function" then
        local ok, schema = pcall(inputSchema, self.def)
        if not ok then
            local err = "Error in inputSchema function: " .. tostring(schema)
            self.state.error = err
            log.error(err)
            parsedSchema = base
        else
            parsedSchema = schema or base
        end
    end
    local res = validation.validate_inputSchema(parsedSchema, self.def.name)
    if not res.ok then
        local err = "Error in inputSchema function: " .. tostring(res.error)
        self.state.error = err
        log.error(err)
        return base
    end
    return parsedSchema
end

function ToolHandler:render(line_offset)
    line_offset = line_offset or 0
    local lines = {}
    vim.list_extend(lines, vim.tbl_map(Text.pad_line, Text.multiline(self:get_description(), highlights.muted)))
    table.insert(lines, Text.pad_line(NuiLine()))
    -- Parameter form
    vim.list_extend(lines, self:render_param_form(line_offset + #lines))

    -- Result if any
    vim.list_extend(lines, self:render_result())

    return lines
end

return ToolHandler
