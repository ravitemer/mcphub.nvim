local highlights = require("mcphub.utils.highlights").groups
local ImageCache = require("mcphub.utils.image_cache")
local NuiLine = require("mcphub.utils.nuiline")
local Text = require("mcphub.utils.text")

---@class CapabilityHandler
---@field server_name string Name of the server this capability belongs to
---@field info table Raw capability info from the server
---@field def table Definition of the capability
---@field state table Current state of the capability execution
---@field interactive_lines { line: number, type: string, context: any}[] List of interactive lines
local CapabilityHandler = {
    type = nil, -- to be set by subclasses
}
CapabilityHandler.__index = CapabilityHandler

function CapabilityHandler:new(server_name, capability_info, view)
    local handler = setmetatable({
        name = capability_info.def
                and (capability_info.def.name or capability_info.def.uri or capability_info.def.uriTemplate)
            or (capability_info.name or ""),
        server_name = server_name,
        info = capability_info,
        def = capability_info.def or {},
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
            -- line_hl_group = highlights.active_item,
            virt_text = { { "Press <CR> to submit", highlights.muted } },
            virt_text_pos = "eol",
        })
    elseif type == "input" then
        view.cursor_highlight = vim.api.nvim_buf_set_extmark(view.ui.buffer, view.hover_ns, line - 1, 0, {
            -- line_hl_group = highlights.active_item,
            virt_text = { { "Press <CR> to edit, 'o' for text box", highlights.muted } },
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

-- Text box handling
function CapabilityHandler:open_text_box(title, content, on_save)
    -- Create a new scratch buffer
    local bufnr = vim.api.nvim_create_buf(false, true)

    -- Set buffer options
    vim.api.nvim_buf_set_option(bufnr, "buftype", "acwrite")
    vim.api.nvim_buf_set_option(bufnr, "bufhidden", "wipe")
    vim.api.nvim_buf_set_option(bufnr, "swapfile", false)

    -- Set initial content
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.split(content or "", "\n"))

    -- Calculate window size and position
    local width = 80
    local height = 10
    local editor_width = vim.o.columns
    local editor_height = vim.o.lines

    local win_opts = {
        relative = "editor",
        width = width,
        height = height,
        col = math.floor((editor_width - width) / 2),
        row = math.floor((editor_height - height) / 2),
        style = "minimal",
        border = "rounded",
        title = " " .. title .. " ",
        title_pos = "center",
    }

    -- Create floating window
    local win = vim.api.nvim_open_win(bufnr, true, win_opts)

    -- Set window options
    vim.api.nvim_win_set_option(win, "number", false)
    vim.api.nvim_win_set_option(win, "relativenumber", false)
    vim.api.nvim_win_set_option(win, "wrap", true)
    vim.api.nvim_win_set_option(win, "cursorline", true)

    -- Create namespace for virtual text
    local ns = vim.api.nvim_create_namespace("MCPHub" .. self.type .. "TextBox")

    -- Function to update virtual text at cursor position
    local function update_virtual_text()
        vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
        if vim.fn.mode() == "n" then
            local cursor = vim.api.nvim_win_get_cursor(0)
            local row = cursor[1] - 1
            vim.api.nvim_buf_set_extmark(bufnr, ns, row, 0, {
                virt_text = { { "Press <CR> to save", "Comment" } },
                virt_text_pos = "eol",
            })
        end
    end

    -- Set up autocmd for cursor movement and mode changes
    local group = vim.api.nvim_create_augroup("MCPHub" .. self.type .. "Cursor", { clear = true })
    vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI", "ModeChanged" }, {
        buffer = bufnr,
        group = group,
        callback = update_virtual_text,
    })

    -- Set buffer local mappings
    local function save_and_close()
        local new_content = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
        new_content = vim.trim(new_content)
        -- Close the window
        vim.api.nvim_win_close(win, true)
        -- Call save callback if content changed
        if content ~= new_content then
            on_save(new_content)
        end
    end

    local function close_window()
        vim.api.nvim_win_close(win, true)
    end

    -- Add mappings for normal mode
    local mappings = {
        ["<CR>"] = save_and_close,
        ["<Esc>"] = close_window,
        ["q"] = close_window,
    }

    -- Apply mappings
    for key, action in pairs(mappings) do
        vim.keymap.set("n", key, action, { buffer = bufnr, silent = true })
    end

    vim.api.nvim_win_set_cursor(win, { vim.api.nvim_buf_line_count(bufnr), 0 })
    update_virtual_text() -- Show initial hint
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

function CapabilityHandler:get_description(def_description)
    local description = def_description or self.def.description or ""
    if type(description) == "function" then
        local ok, desc = pcall(description, self.def)
        if not ok then
            description = "Failed to get description :" .. (desc or "")
        else
            description = "(" .. Text.icons.event .. " Dynamic) " .. (desc or "Nothing returned")
        end
    end
    return description
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
