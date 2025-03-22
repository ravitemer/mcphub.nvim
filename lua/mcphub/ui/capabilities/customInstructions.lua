local Base = require("mcphub.ui.capabilities.base")
local NuiLine = require("mcphub.utils.nuiline")
local State = require("mcphub.state")
local Text = require("mcphub.utils.text")
local highlights = require("mcphub.utils.highlights").groups
local native = require("mcphub.native")

---@class CustomInstructionsHandler : CapabilityHandler
---@field super CapabilityHandler
local CustomInstructionsHandler = setmetatable({}, {
    __index = Base,
})
CustomInstructionsHandler.__index = CustomInstructionsHandler
CustomInstructionsHandler.type = "customInstructions"

function CustomInstructionsHandler:new(server_name, capability_info, view)
    local handler = Base.new(self, server_name, capability_info, view)
    return handler
end

function CustomInstructionsHandler:open_edit_buffer(current_text)
    -- Create a new scratch buffer
    local bufnr = vim.api.nvim_create_buf(false, true)

    -- Set buffer options
    vim.api.nvim_buf_set_option(bufnr, "buftype", "acwrite")
    vim.api.nvim_buf_set_option(bufnr, "bufhidden", "wipe")
    vim.api.nvim_buf_set_option(bufnr, "swapfile", false)

    -- Set initial content
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.split(current_text or "", "\n"))

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
        title = " Custom Instructions ",
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
    local ns = vim.api.nvim_create_namespace("custom_instructions_hints")

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
    local group = vim.api.nvim_create_augroup("CustomInstructionsHints", { clear = true })
    vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI", "ModeChanged" }, {
        buffer = bufnr,
        group = group,
        callback = update_virtual_text,
    })

    -- Set buffer local mappings
    local server_name = self.server_name
    local function save_and_close()
        local content = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
        content = vim.trim(content)
        -- Close the window
        vim.api.nvim_win_close(win, true)
        -- Update only if content has changed
        if content ~= current_text then
            local is_native = native.is_native_server(self.server_name)
            local server_config = (
                is_native and State.native_servers_config[self.server_name] or State.servers_config[self.server_name]
            ) or {}
            local custom_instructions = server_config.custom_instructions or {}
            if State.hub_instance then
                State.hub_instance:update_server_config(server_name, {
                    custom_instructions = vim.tbl_extend("force", custom_instructions, { text = content }),
                })
            end
        end
    end

    local function close_window()
        vim.api.nvim_win_close(win, true)
    end

    -- Add all mappings for both normal and insert modes
    local mappings = {
        ["n"] = {
            ["<CR>"] = save_and_close,
            ["<Esc>"] = close_window,
            ["q"] = close_window,
        },
    }

    for mode, mode_mappings in pairs(mappings) do
        for key, action in pairs(mode_mappings) do
            vim.keymap.set(mode, key, action, { buffer = bufnr, silent = true })
        end
    end

    vim.api.nvim_win_set_cursor(win, { vim.api.nvim_buf_line_count(bufnr), 0 })
    update_virtual_text() -- Show initial hint
end

function CustomInstructionsHandler:handle_action(line)
    local type = self:get_line_info(line)
    if type == "edit" then
        -- Edit custom instructions
        local is_native = native.is_native_server(self.server_name)
        local server_config = (
            is_native and State.native_servers_config[self.server_name] or State.servers_config[self.server_name]
        ) or {}
        local custom_instructions = server_config.custom_instructions or {}
        local text = custom_instructions.text or ""

        -- Open edit buffer instead of input prompt
        self:open_edit_buffer(text)
    end
end

function CustomInstructionsHandler:render(line_offset)
    line_offset = line_offset or 0
    self:clear_line_tracking()

    local lines = {}

    -- Custom Instructions info section
    vim.list_extend(lines, self:render_section_start(Text.icons.instructions .. " Custom Instructions"))

    local is_native = native.is_native_server(self.server_name)
    local server_config = (
        is_native and State.native_servers_config[self.server_name] or State.servers_config[self.server_name]
    ) or {}
    local custom_instructions = server_config.custom_instructions or {}
    local is_disabled = custom_instructions.disabled
    local text = custom_instructions.text or ""

    -- Status line
    local details = {}

    -- Add spacer
    table.insert(details, NuiLine():append(""))
    if text ~= "" then
        -- Add instructions text
        vim.list_extend(details, Text.multiline(text, is_disabled and highlights.muted or highlights.info))
    else
        -- Add instructions text
        vim.list_extend(details, Text.multiline("No custom instructions added.", highlights.muted))
    end

    vim.list_extend(lines, self:render_section_content(details, 2))
    vim.list_extend(lines, self:render_section_end())

    -- Actions section
    table.insert(lines, Text.pad_line(NuiLine()))
    vim.list_extend(lines, self:render_section_start("Actions"))

    local edit_line = NuiLine():append("[ " .. Text.icons.edit .. " Edit ]", highlights.success_fill)
    vim.list_extend(lines, self:render_section_content({ NuiLine(), edit_line }, 2))
    -- Track button line for interaction
    self:track_line(line_offset + #lines, "edit")

    vim.list_extend(lines, self:render_section_end())

    return lines
end

return CustomInstructionsHandler
