--[[
--NOTE: Having cmd = "MCPHub" or lazy = true in user's lazy config, and adding lualine component using require("mcphub.extensions.lualine") will start the hub indirectly.
--]]

-- DEPRECATED: This lualine component will load MCPHub even with lazy loading.
-- Use the global variables approach instead: vim.g.mcphub_status, vim.g.mcphub_servers_count, vim.g.mcphub_executing
-- See documentation for recommended usage: doc/extensions/lualine.md

local M = require("lualine.component"):extend()
local utils = require("lualine.utils.utils")
local spinner_frames = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
local spinner_interval = 80 -- ms between frames
local timer = nil
local current_frame = 1

local default_options = {
    icon = "󰐻",
    colored = true,
    colors = {
        connected = { fg = utils.extract_highlight_colors("DiagnosticInfo", "fg") },
        connecting = { fg = utils.extract_highlight_colors("DiagnosticWarn", "fg") },
        error = { fg = utils.extract_highlight_colors("DiagnosticError", "fg") },
    },
}

M.HubState = {
    STARTING = "starting",
    READY = "ready",
    ERROR = "error",
    RESTARTING = "restarting",
    RESTARTED = "restarted",
    STOPPED = "stopped",
    STOPPING = "stopping",
}

vim.g.mcphub_status = M.HubState.STARTING
-- Initialize the component
function M:init(options)
    vim.notify_once(
        "MCPHub lualine extension is deprecated. Use global variables instead for better lazy-loading. See :help mcphub-lualine",
        vim.log.levels.WARN
    )
    M.super.init(self, options)
    self:create_autocommands()
    self.options = vim.tbl_deep_extend("keep", self.options or {}, default_options)
    self.highlights = {
        error = self:create_hl(self.options.colors.error, "error"),
        connecting = self:create_hl(self.options.colors.connecting, "connecting"),
        connected = self:create_hl(self.options.colors.connected, "connected"),
    }
    -- Determine whether the plugin's own coloring logic should apply to the icon or status text.
    self.plugin_colors_icon = self.options.colored and not self.options.icon_color_highlight
    self.plugin_colors_status = self.options.colored and not self.options.color_highlight
end

function M:create_autocommands()
    local group = vim.api.nvim_create_augroup("mcphub_lualine", { clear = true })

    -- Handle state changes
    vim.api.nvim_create_autocmd("User", {
        group = group,
        pattern = "MCPHubStateChange",
        callback = function(args)
            self:manage_spinner()
            if args.data then
                vim.g.mcphub_status = args.data.state
                vim.g.mcphub_active_servers = args.data.active_servers
            end
        end,
    })

    -- Tool/Resource activity events
    vim.api.nvim_create_autocmd("User", {
        group = group,
        pattern = { "MCPHub*" },
        callback = function(args)
            -- Update based on event pattern
            if args.match == "MCPHubToolStart" then
                vim.g.mcphub_executing = true
                vim.g.mcphub_tool_active = true
                vim.g.mcphub_tool_info = args.data
            elseif args.match == "MCPHubToolEnd" then
                vim.g.mcphub_executing = false
                vim.g.mcphub_tool_active = false
                vim.g.mcphub_tool_info = nil
            elseif args.match == "MCPHubResourceStart" then
                vim.g.mcphub_executing = true
                vim.g.mcphub_resource_active = true
                vim.g.mcphub_resource_info = args.data
            elseif args.match == "MCPHubResourceEnd" then
                vim.g.mcphub_executing = false
                vim.g.mcphub_resource_active = false
                vim.g.mcphub_resource_info = nil
            elseif args.match == "MCPHubPromptStart" then
                vim.g.mcphub_executing = true
                vim.g.mcphub_prompt_active = true
                vim.g.mcphub_prompt_info = args.data
            elseif args.match == "MCPHubPromptEnd" then
                vim.g.mcphub_executing = false
                vim.g.mcphub_prompt_active = false
                vim.g.mcphub_prompt_info = nil
            elseif args.match == "MCPHubServersUpdated" then
                if args.data then
                    vim.g.mcphub_active_servers = args.data.active_servers
                end
            end
            -- Manage animation
            self:manage_spinner()
        end,
    })
end

function M.is_connected()
    return vim.g.mcphub_status == M.HubState.READY or vim.g.mcphub_status == M.HubState.RESTARTED
end

function M.is_connecting()
    return vim.g.mcphub_status == M.HubState.STARTING or vim.g.mcphub_status == M.HubState.RESTARTING
end

function M:manage_spinner()
    local should_show = vim.g.mcphub_executing and M.is_connected()
    if should_show and not timer then
        timer = vim.loop.new_timer()
        if timer then
            timer:start(
                0,
                spinner_interval,
                vim.schedule_wrap(function()
                    current_frame = (current_frame % #spinner_frames) + 1
                    vim.cmd("redrawstatus")
                end)
            )
        end
    elseif not should_show and timer then
        timer:stop()
        timer:close()
        timer = nil
        current_frame = 1
    end
end

-- Get appropriate status icon and highlight
function M:get_status_display()
    local tower = "󰐻"
    return tower, M.is_connected() and "DiagnosticInfo" or M.is_connecting() and "DiagnosticWarn" or "DiagnosticError"
end

-- Update function that lualine calls
function M:update_status()
    -- Show either the spinner or the number of active servers
    local count_or_spinner = vim.g.mcphub_executing and spinner_frames[current_frame]
        or tostring(vim.g.mcphub_active_servers or 0)

    -- Set the group highlight appropriately.
    local highlight = M.is_connected() and self.highlights.connected
        or M.is_connecting() and self.highlights.connecting
        or self.highlights.error

    if self.plugin_colors_icon then
        self.options.icon_color_highlight = highlight
    end
    if self.plugin_colors_status then
        self.options.color_highlight = highlight
    end

    return count_or_spinner
end

-- Cleanup
function M:disable()
    if timer then
        timer:stop()
        timer:close()
        timer = nil
    end
end

return M
