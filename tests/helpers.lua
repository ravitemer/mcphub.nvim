local Helpers = {}

---Mock the plugin config
---@return table
local function mock_config()
    local config_module = require("mcphub.config")
    ---@diagnostic disable-next-line: duplicate-set-field
    config_module.setup = function(args)
        config_module.config = args or {}
    end
    return config_module
end

---Set up the CodeCompanion plugin with test configuration
---@return MCPHub.Hub, MCPHub.State
Helpers.setup_plugin = function(config)
    local test_config = require("tests.config")
    test_config = vim.tbl_deep_extend("force", test_config, config or {})
    local config_module = mock_config()
    config_module.setup(test_config)
    local State = require("mcphub.state")
    State = vim.tbl_deep_extend("force", State, require("tests.state"))
    State.setup_state = "completed"
    State.hub_instance = require("mcphub.hub"):new(test_config)
    State.hub_instance.ready = true
    State.config = test_config
    -- local hub_instance = require("mcphub").setup(test_config) --[[@as MCPHub.Hub]]
    return State.hub_instance, State
end

-- Monkey-patch `MiniTest.new_child_neovim` with helpful wrappers
Helpers.new_child_neovim = function()
    local child = MiniTest.new_child_neovim()

    local prevent_hanging = function(method)
        if not child.is_blocked() then
            return
        end

        local msg = string.format("Can not use `child.%s` because child process is blocked.", method)
        error(msg)
    end

    child.setup = function()
        child.restart({ "-u", "scripts/minimal_init.lua" })
        child.o.statusline = ""
        child.o.laststatus = 0
        -- Change initial buffer to be readonly. This not only increases execution
        -- speed, but more closely resembles manually opened Neovim.
        child.bo.readonly = true
    end

    child.set_lines = function(arr, start, finish)
        prevent_hanging("set_lines")

        if type(arr) == "string" then
            arr = vim.split(arr, "\n")
        end

        child.api.nvim_buf_set_lines(0, start or 0, finish or -1, false, arr)
    end

    child.get_lines = function(start, finish)
        prevent_hanging("get_lines")

        return child.api.nvim_buf_get_lines(0, start or 0, finish or -1, false)
    end

    child.set_cursor = function(line, column, win_id)
        prevent_hanging("set_cursor")

        child.api.nvim_win_set_cursor(win_id or 0, { line, column })
    end

    child.get_cursor = function(win_id)
        prevent_hanging("get_cursor")

        return child.api.nvim_win_get_cursor(win_id or 0)
    end

    child.set_size = function(lines, columns)
        prevent_hanging("set_size")

        if type(lines) == "number" then
            child.o.lines = lines
        end

        if type(columns) == "number" then
            child.o.columns = columns
        end
    end

    child.get_size = function()
        prevent_hanging("get_size")

        return { child.o.lines, child.o.columns }
    end

    --- Assert visual marks
    ---
    --- Useful to validate visual selection
    ---
    ---@param first number|table Table with start position or number to check linewise.
    ---@param last number|table Table with finish position or number to check linewise.
    ---@private
    child.expect_visual_marks = function(first, last)
        child.ensure_normal_mode()

        first = type(first) == "number" and { first, 0 } or first
        last = type(last) == "number" and { last, 2147483647 } or last

        MiniTest.expect.equality(child.api.nvim_buf_get_mark(0, "<"), first)
        MiniTest.expect.equality(child.api.nvim_buf_get_mark(0, ">"), last)
    end

    child.expect_screenshot = function(opts, path)
        opts = opts or {}
        local screenshot_opts = { redraw = opts.redraw }
        opts.redraw = nil
        MiniTest.expect.reference_screenshot(child.get_screenshot(screenshot_opts), path, opts)
    end

    -- Poke child's event loop to make it up to date
    child.poke_eventloop = function()
        child.api.nvim_eval("1")
    end

    return child
end

-- Detect CI
Helpers.is_ci = function()
    return os.getenv("CI") ~= nil
end
Helpers.skip_in_ci = function(msg)
    if Helpers.is_ci() then
        MiniTest.skip(msg or "Does not test properly in CI")
    end
end

-- Detect OS
Helpers.is_windows = function()
    return vim.fn.has("win32") == 1
end
Helpers.skip_on_windows = function(msg)
    if Helpers.is_windows() then
        MiniTest.skip(msg or "Does not test properly on Windows")
    end
end

Helpers.is_macos = function()
    return vim.fn.has("mac") == 1
end
Helpers.skip_on_macos = function(msg)
    if Helpers.is_macos() then
        MiniTest.skip(msg or "Does not test properly on MacOS")
    end
end

Helpers.is_linux = function()
    return vim.fn.has("linux") == 1
end
Helpers.skip_on_linux = function(msg)
    if Helpers.is_linux() then
        MiniTest.skip(msg or "Does not test properly on Linux")
    end
end

-- Standardized way of dealing with time
Helpers.is_slow = function()
    -- Create sample chat data for testing
    return Helpers.is_ci() and (Helpers.is_windows() or Helpers.is_macos())
end

Helpers.skip_if_slow = function(msg)
    if Helpers.is_slow() then
        MiniTest.skip(msg or "Does not test properly in slow context")
    end
end

Helpers.get_time_const = function(delay)
    local coef = 1
    if Helpers.is_ci() then
        if Helpers.is_linux() then
            coef = 2
        end
        if Helpers.is_windows() then
            coef = 5
        end
        if Helpers.is_macos() then
            coef = 15
        end
    end
    return coef * delay
end

Helpers.sleep = function(ms, child, skip_slow)
    if skip_slow then
        Helpers.skip_if_slow("Skip because state checks after sleep are hard to make robust in slow context")
    end
    vim.loop.sleep(math.max(ms, 1))
    if child ~= nil then
        child.poke_eventloop()
    end
end

-- Standardized way of setting number of retries
Helpers.get_n_retry = function(n)
    local coef = 1
    if Helpers.is_ci() then
        if Helpers.is_linux() then
            coef = 2
        end
        if Helpers.is_windows() then
            coef = 3
        end
        if Helpers.is_macos() then
            coef = 4
        end
    end
    return coef * n
end

return Helpers
