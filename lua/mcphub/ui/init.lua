---@brief [[
--- UI Core for MCPHub
--- Handles window/buffer management and view system
---@brief ]]
---@class MCPHubUI
local State = require("mcphub.state")
local Text = require("mcphub.utils.text")
local hl = require("mcphub.utils.highlights")

local UI = {}
UI.__index = UI

-- Constants for window sizing and layout
local WINDOW_CONSTANTS = {
    WIDTH_RATIO = 0.9,
    HEIGHT_RATIO = 0.9,
    MIN_WIDTH = 40,
}

--- Create a new UI instance
---@return MCPHubUI
function UI:new()
    local instance = {
        window = nil, -- Window handle
        buffer = nil, -- Buffer handle
        current_view = nil, -- Current view name
        views = {}, -- View instances
        is_shown = false, -- Whether the UI is currently visible
        cursor_states = {}, -- Store cursor positions by view name
    }
    setmetatable(instance, self)

    -- Setup highlights with auto-update
    hl.setup()
    hl.setup_auto_update()

    -- Initialize views
    instance:init_views()

    -- Subscribe to state changes
    State:subscribe(function(_, changes)
        -- Only update UI if window is visible and relevant state changed
        -- vim.notify("State changed" .. vim.inspect(changes))
        if instance.window and vim.api.nvim_win_is_valid(instance.window) then
            -- Check if we need to update
            local should_update = false
            for k, _ in pairs(changes) do
                if
                    k == "server_output"
                    or k == "setup_state"
                    or k == "server_state"
                    or k == "servers_config"
                    or k == "native_servers_config"
                    or k == "marketplace_state"
                    or k == "logs"
                    or k == "errors"
                then
                    should_update = true
                    break
                end
            end
            if should_update then
                -- Re-render current view
                instance:render()
            end
        end
    end, { "ui", "server", "setup", "errors", "marketplace" })

    -- Create cleanup autocommands
    local group = vim.api.nvim_create_augroup("mcphub_ui", {
        clear = true,
    })

    -- Handle VimLeave
    vim.api.nvim_create_autocmd("VimLeavePre", {
        group = group,
        callback = function()
            instance:cleanup()
        end,
    })

    -- Handle window close
    vim.api.nvim_create_autocmd("WinClosed", {
        group = group,
        callback = function(args)
            -- Check if the closed window is our window
            if instance.window and tonumber(args.match) == instance.window then
                instance:cleanup()
            end
        end,
    })

    return instance
end

--- Initialize views
---@private
function UI:init_views()
    local MainView = require("mcphub.ui.views.main")

    -- Create view instances
    self.views = {
        main = MainView:new(self),
        logs = require("mcphub.ui.views.logs"):new(self),
        help = require("mcphub.ui.views.help"):new(self),
        config = require("mcphub.ui.views.config"):new(self),
        marketplace = require("mcphub.ui.views.marketplace"):new(self),
    }

    -- Set initial view
    self.current_view = "main"
end

--- Create a new buffer for the UI
---@private
function UI:create_buffer()
    -- Create new buffer
    self.buffer = vim.api.nvim_create_buf(false, true)

    -- Set buffer options
    vim.api.nvim_buf_set_option(self.buffer, "modifiable", false)
    vim.api.nvim_buf_set_option(self.buffer, "bufhidden", "wipe")
    vim.api.nvim_buf_set_option(self.buffer, "filetype", "mcphub")
    vim.api.nvim_buf_set_option(self.buffer, "wrap", true)

    -- Set buffer mappings
    self:setup_keymaps()

    return self.buffer
end

--- Create a new window for the UI
---@private
function UI:create_window()
    if not self.buffer or not vim.api.nvim_buf_is_valid(self.buffer) then
        self:create_buffer()
    end

    -- Calculate dimensions with padding
    local width = math.max(WINDOW_CONSTANTS.MIN_WIDTH, math.floor(vim.o.columns * WINDOW_CONSTANTS.WIDTH_RATIO))
    -- Account for horizontal padding
    width = width - (Text.HORIZONTAL_PADDING * 2)

    local height = math.floor(vim.o.lines * WINDOW_CONSTANTS.HEIGHT_RATIO)
    local row = math.floor((vim.o.lines - height) / 2)
    local col = math.floor((vim.o.columns - width) / 2)

    -- Create floating window
    self.window = vim.api.nvim_open_win(self.buffer, true, {
        relative = "editor",
        width = width,
        height = height,
        row = row,
        col = col,
        style = "minimal",
        border = "rounded",
    })

    -- Apply window highlights
    vim.api.nvim_win_set_option(
        self.window,
        "winhl",
        "Normal:" .. hl.groups.window_normal .. ",FloatBorder:" .. hl.groups.window_border
    )

    return self.window
end

--- Set up view-specific keymaps
function UI:setup_keymaps()
    local function map(key, action, desc)
        vim.keymap.set("n", key, action, {
            buffer = self.buffer,
            desc = desc,
            nowait = true,
        })
    end

    -- Global navigation
    map("H", function()
        self:switch_view("main")
    end, "Switch to Home view")
    map("M", function()
        self:switch_view("marketplace")
    end, "Switch to Marketplace")

    map("C", function()
        self:switch_view("config")
    end, "Switch to Config view")

    map("L", function()
        self:switch_view("logs")
    end, "Switch to Logs view")

    map("?", function()
        self:switch_view("help")
    end, "Switch to Help view")

    -- Close window
    map("q", function()
        self:cleanup()
    end, "Close")

    map("r", function()
        self:hard_refresh()
    end, "Refresh")
    map("R", function()
        self:restart()
    end, "Restart")
end

function UI:refresh()
    if State.hub_instance then
        vim.notify("Refreshing")
        if State.hub_instance:refresh() then
            vim.notify("Refreshed")
        else
            vim.notify("Failed to refresh")
        end
    else
        vim.notify("No hub instance available")
    end
end

function UI:restart()
    if State.hub_instance then
        vim.notify("Restarting")
        State.hub_instance:restart(function(success)
            if success then
                vim.notify("Restarted")
            else
                vim.notify("Failed to restart")
            end
        end)
    else
        vim.notify("No hub instance available")
    end
end

function UI:hard_refresh()
    if State.hub_instance then
        vim.notify("Updating all server capabilities")
        if State.hub_instance:hard_refresh() then
            vim.notify("Refreshed")
        else
            vim.notify("Failed to refresh")
        end
    else
        vim.notify("No hub instance available")
    end
end

-- function UI:restart()
--     if State.hub_instance then
--         vim.notify("Restarting")
--         State.hub_instance:restart(function(success)
--             if success then
--                 vim.notify("Restarted")
--             else
--                 vim.notify("Failed to restart")
--             end
--         end)
--     else
--         vim.notify("No hub instance available")
--     end
-- end

--- Clean up resources
---@private
function UI:cleanup()
    if not (self.window and vim.api.nvim_win_is_valid(self.window)) then
        return
    end

    -- Clean up buffer if it exists
    if self.buffer and vim.api.nvim_buf_is_valid(self.buffer) then
        vim.api.nvim_buf_delete(self.buffer, {
            force = true,
        })
        self.buffer = nil
    end

    -- Close window if it exists
    if self.window and vim.api.nvim_win_is_valid(self.window) then
        vim.api.nvim_win_close(self.window, true)
        self.window = nil
    end
    self.is_shown = false
end

--- Toggle UI visibility
function UI:toggle()
    if self.window and vim.api.nvim_win_is_valid(self.window) then
        self:cleanup()
    else
        self:show()
    end
end

--- Switch to a different view
---@param view_name string Name of view to switch to
function UI:switch_view(view_name)
    -- Leave current view if any
    if self.current_view and self.views[self.current_view] and self.is_shown then
        self.views[self.current_view]:before_leave()
        self.views[self.current_view]:after_leave()
    end

    -- Switch view
    self.current_view = view_name

    -- Enter new view
    if self.views[view_name] then
        self.views[view_name]:before_enter()
        self.views[view_name]:draw()
        self.views[view_name]:after_enter()
    end
end

--- Show the UI window
function UI:show()
    -- Create/show window if needed
    if not self.window or not vim.api.nvim_win_is_valid(self.window) then
        self:create_window()
    end

    -- Focus window
    vim.api.nvim_set_current_win(self.window)

    -- Draw current view
    self:render()
    self.is_shown = true
end

--- Render current view
---@private
function UI:render()
    self:switch_view(self.current_view)
end

return UI
