local highlights = require("mcphub.utils.highlights").groups
local ImageCache = require("mcphub.utils.image_cache")
local NuiLine = require("mcphub.utils.nuiline")
local Text = require("mcphub.utils.text")

---@class CapabilityHandler
---@field server_name string Name of the server this capability belongs to
---@field info table Raw capability info from the server
---@field state table Current state of the capability execution
---@field interactive_lines { line: number, type: string, context: any}[] List of interactive lines
local CapabilityHandler = {
    type = nil, -- to be set by subclasses
}
CapabilityHandler.__index = CapabilityHandler

function CapabilityHandler:new(server_name, capability_info, view)
    local handler = setmetatable({
        server_name = server_name,
        info = capability_info,
        view = view,
        state = {
            is_executing = false,
            result = nil,
            error = nil,
        },
        interactive_lines = {},
    }, self)
    return handler
end

--- Get preferred cursor position when entering capability mode
---@return number|nil Line number to position cursor at
function CapabilityHandler:get_cursor_position()
    -- Default to first interactive line if any
    if #self.interactive_lines > 0 then
        return { self.interactive_lines[1].line, 2 }
    end
    return nil
end

-- Line tracking for interactivity
function CapabilityHandler:track_line(line_nr, type, context)
    table.insert(self.interactive_lines, {
        line = line_nr,
        type = type,
        context = context,
    })
end

function CapabilityHandler:clear_line_tracking()
    self.interactive_lines = {}
end

function CapabilityHandler:get_line_info(line_nr)
    for _, tracked in ipairs(self.interactive_lines) do
        if tracked.line == line_nr then
            return tracked.type, tracked.context
        end
    end
    return nil, nil
end

-- Common highlighting
function CapabilityHandler:handle_cursor_move(view, line)
    local type, context = self:get_line_info(line)
    if not type then
        return
    end

    if type == "submit" and not self.state.is_executing then
        view.cursor_highlight = vim.api.nvim_buf_set_extmark(view.ui.buffer, view.hover_ns, line - 1, 0, {
            line_hl_group = highlights.active_item,
            virt_text = { { "Press <CR> to submit", highlights.active_item_muted } },
            virt_text_pos = "eol",
        })
    elseif type == "input" then
        view.cursor_highlight = vim.api.nvim_buf_set_extmark(view.ui.buffer, view.hover_ns, line - 1, 0, {
            line_hl_group = highlights.active_item,
            virt_text = { { "Press <CR> to edit", highlights.active_item_muted } },
            virt_text_pos = "eol",
        })
    end
end

-- Input handling
function CapabilityHandler:handle_input(prompt, default, callback)
    vim.ui.input({
        prompt = prompt,
        default = default or "",
    }, function(input)
        if input ~= nil then -- Only handle if not cancelled
            callback(input)
        end
    end)
end

-- Common section rendering utilities
function CapabilityHandler:render_section_start(title, highlight)
    local lines = {}
    table.insert(
        lines,
        Text.pad_line(
            NuiLine():append("╭─", highlights.muted):append(" " .. title .. " ", highlight or highlights.header)
        )
    )
    return lines
end

function CapabilityHandler:render_section_content(content, indent_level)
    local lines = {}
    local padding = string.rep(" ", indent_level or 1)
    for _, line in ipairs(content) do
        local rendered_line = NuiLine()
        if type(line) == "string" then
            rendered_line:append("│", highlights.muted):append(padding, highlights.muted):append(line)
        else
            rendered_line:append("│", highlights.muted):append(padding, highlights.muted):append(line)
        end
        table.insert(lines, Text.pad_line(rendered_line))
    end
    return lines
end

function CapabilityHandler:render_section_end()
    return { Text.pad_line(NuiLine():append("╰─", highlights.muted)) }
end

-- Common result rendering
function CapabilityHandler:render_result()
    if not self.state.result then
        return {}
    end

    local lines = {}
    table.insert(lines, Text.pad_line(NuiLine())) -- Empty line
    vim.list_extend(lines, self:render_section_start("Result"))

    -- Handle text content
    if self.state.result.text and self.state.result.text ~= "" then
        vim.list_extend(lines, self:render_section_content(Text.multiline(self.state.result.text, highlights.info), 1))
    end

    -- Handle image content
    if self.state.result.images and #self.state.result.images > 0 then
        if #lines > 0 then
            vim.list_extend(lines, self:render_section_content({ "  " }, 1))
        end
        for i, img in ipairs(self.state.result.images) do
            -- Save to temp file
            local ok, filepath = pcall(ImageCache.save_image, img.data, img.mimeType or "application/octet-stream")
            if ok and filepath then
                -- Create filesystem URL
                local url = "file://" .. filepath
                -- Show friendly name with URL
                local image_line = NuiLine()
                    :append("Image " .. i .. ": ", highlights.muted)
                    :append(" [", highlights.muted)
                    :append(url, highlights.link)
                    :append("]", highlights.muted)
                vim.list_extend(lines, self:render_section_content({ image_line }, 1))
            else
                vim.list_extend(lines, self:render_section_content({ "Failed to save image: " .. filepath }, 1))
            end
        end
    end

    --Handle blobs content
    if self.state.result.blobs and #self.state.result.blobs > 0 then
        if #lines > 0 then
            vim.list_extend(lines, self:render_section_content({ "  " }, 1))
        end
        for i, blob in ipairs(self.state.result.blobs) do
            local blob_line = NuiLine():append("Blob " .. i .. ": Blob data cannot be shown", highlights.muted)
            vim.list_extend(lines, self:render_section_content({ blob_line }, 1))
        end
    end

    vim.list_extend(lines, self:render_section_end())
    return lines
end

-- Error handling
function CapabilityHandler:handle_response(response, err)
    self.state.is_executing = false
    if err then
        vim.notify(string.format("%s execution failed: %s", self.type, err), vim.log.levels.ERROR)
        self.state.error = err
    else
        self.state.result = response
        self.state.error = nil
    end
end

-- Abstract methods to be implemented by subclasses
function CapabilityHandler:execute()
    error(string.format("execute() not implemented for capability type: %s", self.type))
end

function CapabilityHandler:handle_action(line)
    error(string.format("handle_action() not implemented for capability type: %s", self.type))
end

function CapabilityHandler:render(line_offset)
    error(string.format("render() not implemented for capability type: %s", self.type))
end

return CapabilityHandler
