--[[
--NOTE: Having cmd = "MCPHub" or lazy = true in user's lazy config, and adding lualine component using require("mcphub.extensions.lualine") will start the hub indirectly.
--]]
local M = require("lualine.component"):extend()
-- local Text = require("mcphub.utils.text")
-- Spinner animation frames
local spinner_frames = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
local spinner_interval = 80 -- ms between frames
local timer = nil
local current_frame = 1

vim.g.mcphub_status = "connecting"
-- Initialize the component
function M:init(options)
    M.super.init(self, options)
    self:create_autocommands()
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
                vim.g.mcphub_status = args.data.status
                vim.g.mcphub_active_servers = args.data.active_servers
                vim.g.mcphub_total_tools = args.data.total_tools
                vim.g.mcphub_total_resources = args.data.total_resources
            end
        end,
    })

    -- Tool/Resource activity events
    vim.api.nvim_create_autocmd("User", {
        group = group,
        pattern = { "MCPHubToolStart", "MCPHubToolEnd", "MCPHubResourceStart", "MCPHubResourceEnd" },
        callback = function(args)
            -- Update based on event pattern
            if args.match == "MCPHubToolStart" then
                vim.g.mcphub_tool_active = true
                vim.g.mcphub_tool_info = args.data
            elseif args.match == "MCPHubToolEnd" then
                vim.g.mcphub_tool_active = false
                vim.g.mcphub_tool_info = nil
            elseif args.match == "MCPHubResourceStart" then
                vim.g.mcphub_resource_active = true
                vim.g.mcphub_resource_info = args.data
            elseif args.match == "MCPHubResourceEnd" then
                vim.g.mcphub_resource_active = false
                vim.g.mcphub_resource_info = nil
            end
            -- Manage animation
            self:manage_spinner()
        end,
    })
end

function M:manage_spinner()
    local should_show = vim.g.mcphub_tool_active or vim.g.mcphub_resource_active or vim.g.mcphub_status == "connecting"
    if should_show and not timer then
        timer = vim.loop.new_timer()
        timer:start(
            0,
            spinner_interval,
            vim.schedule_wrap(function()
                current_frame = (current_frame % #spinner_frames) + 1
                vim.cmd("redrawstatus")
            end)
        )
    elseif not should_show and timer then
        timer:stop()
        timer:close()
        timer = nil
        current_frame = 1
    end
end

-- Get appropriate status icon and highlight
function M:get_status_display()
    local status = vim.g.mcphub_status or "disconnected"
    local tower = "󰐻"
    return tower,
        status == "connected" and "DiagnosticInfo" or status == "connecting" and "DiagnosticWarn" or "DiagnosticError"
end

-- Format with highlight
function M:format_hl(text, hl)
    if hl then
        return string.format("%%#%s#%s%%*", hl, text)
    end
    return text
end

-- Update function that lualine calls
function M:update_status()
    -- Get status display
    local status_icon, status_hl = self:get_status_display()

    -- Show either the spinner or the number of active servers
    local count_or_spinner = (vim.g.mcphub_tool_active or vim.g.mcphub_resource_active)
            and spinner_frames[current_frame]
        or tostring(vim.g.mcphub_active_servers or 0)

    -- Format the status line
    return self:format_hl(status_icon .. " " .. count_or_spinner .. " ", status_hl)
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
