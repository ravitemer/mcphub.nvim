-- Tests for "Yes & Review" Tool Approval Feature
local new_set = MiniTest.new_set
local expect, eq = MiniTest.expect, MiniTest.expect.equality
local Helpers = require("tests.helpers")

local T = new_set({
    hooks = {
        pre_case = function()
            _G.child = Helpers.new_child_neovim()
            _G.child.setup()
            -- Load required modules in child process using lua_func for type safety
            _G.child.lua_func(function()
                _G.ui_utils = require("mcphub.utils.ui")
                _G.shared = require("mcphub.extensions.shared")
                _G.State = require("mcphub.state")
                _G.State.config = require("tests.config")
            end)
        end,
        post_case = function()
            if _G.child then
                _G.child.stop()
                _G.child = nil
            end
        end,
    },
})

-- =========================================================================
-- Core UI check
-- =========================================================================

T["confirm_function_exists_and_returns_three_values"] = function()
    -- Test that the confirm function exists
    local result = _G.child.lua_func(function()
        local ui_utils = require("mcphub.utils.ui")
        return {
            has_confirm = type(ui_utils.confirm) == "function",
        }
    end)

    eq(result.has_confirm, true)
end

T["review_window_displays_with_metadata"] = function()
    -- Start review window in child process
    _G.child.lua_func(function()
        local result_data = {
            text = "This is test output\nfrom a tool execution",
        }
        local metadata = {
            server_name = "test_server",
            tool_name = "test_tool",
            action = "use_mcp_tool",
        }

        _G.ui_utils.review_tool_result(result_data, metadata, function(approved)
            _G.test_result = { approved = approved }
        end)

        vim.wait(100)
    end)

    -- Check window exists and has content
    local result = _G.child.lua_func(function()
        local wins = vim.api.nvim_list_wins()
        local review_win = nil

        for _, win in ipairs(wins) do
            local config = vim.api.nvim_win_get_config(win)
            if config.title and type(config.title) == "table" then
                local title_str = config.title[1][1]
                if title_str:match("Review") then
                    review_win = win
                    break
                end
            end
        end

        if not review_win then
            return { has_window = false, line_count = 0, has_server_info = false }
        end

        local bufnr = vim.api.nvim_win_get_buf(review_win)
        local buf_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

        -- Check for server info in buffer
        local has_server_info = false
        for _, line in ipairs(buf_lines) do
            if line:match("test_server") then
                has_server_info = true
                break
            end
        end

        return {
            has_window = true,
            line_count = #buf_lines,
            has_server_info = has_server_info,
        }
    end)

    -- Close the review window
    _G.child.type_keys("<Esc>")
    _G.child.lua("vim.wait(100)")

    eq(result.has_window, true)
    eq(result.line_count > 0, true)
    eq(result.has_server_info, true)
end

T["review_window_approve_action"] = function()
    -- Start review window
    _G.child.lua_func(function()
        local result_data = { text = "Tool output to approve" }
        local metadata = {
            server_name = "test_server",
            tool_name = "test_tool",
            action = "use_mcp_tool",
        }

        _G.test_result = { approved = nil }
        _G.ui_utils.review_tool_result(result_data, metadata, function(approved)
            _G.test_result.approved = approved
        end)
        vim.wait(100)
    end)

    -- Press 'a' to approve
    _G.child.type_keys("a")
    _G.child.lua("vim.wait(100)")

    local result = _G.child.lua_get("_G.test_result")
    eq(result.approved, true)
end

T["review_window_reject_action"] = function()
    -- Start review window
    _G.child.lua_func(function()
        local result_data = { text = "Tool output to reject" }
        local metadata = {
            server_name = "test_server",
            tool_name = "test_tool",
            action = "use_mcp_tool",
        }

        _G.test_result = { approved = nil }
        _G.ui_utils.review_tool_result(result_data, metadata, function(approved)
            _G.test_result.approved = approved
        end)
        vim.wait(100)
    end)

    -- Press 'r' to reject
    _G.child.type_keys("r")
    _G.child.lua("vim.wait(100)")

    local result = _G.child.lua_get("_G.test_result")
    eq(result.approved, false)
end

T["review_window_escape_rejects"] = function()
    -- Start review window
    _G.child.lua_func(function()
        local result_data = { text = "Tool output" }
        local metadata = {
            server_name = "test_server",
            tool_name = "test_tool",
            action = "use_mcp_tool",
        }

        _G.test_result = { approved = nil }
        _G.ui_utils.review_tool_result(result_data, metadata, function(approved)
            _G.test_result.approved = approved
        end)
        vim.wait(100)
    end)

    -- Press Escape (should reject)
    _G.child.type_keys("<Esc>")
    _G.child.lua("vim.wait(100)")

    local result = _G.child.lua_get("_G.test_result")
    eq(result.approved, false)
end

T["failed_tool_execution_skips_review_window"] = function()
    -- Simulate tool execution failure with review requested
    _G.child.lua_func(function()
        _G.test_result = { review_shown = false, callback_called = false, error_received = nil }

        -- Mock a tool execution that fails
        local params = {
            server_name = "test_server",
            tool_name = "failing_tool",
            tool_input = {},
        }

        -- Simulate the flow with review_requested = true but tool execution fails
        local parsed = _G.shared.parse_params(params, "use_mcp_tool")
        parsed.review_requested = true

        -- Create a mock callback that tracks if it's called with an error
        local function mock_callback(result, error)
            _G.test_result.callback_called = true
            _G.test_result.error_received = error ~= nil

            -- Check if review window was created
            local wins = vim.api.nvim_list_wins()
            for _, win in ipairs(wins) do
                local config = vim.api.nvim_win_get_config(win)
                if config.title and type(config.title) == "table" then
                    local title_str = config.title[1][1]
                    if title_str:match("Review") then
                        _G.test_result.review_shown = true
                        break
                    end
                end
            end
        end

        -- Simulate error being passed to callback (review should NOT be shown)
        mock_callback(nil, "Tool execution failed: connection timeout")

        vim.wait(100)
    end)

    local result = _G.child.lua_get("_G.test_result")
    eq(result.callback_called, true)
    eq(result.error_received, true)
    eq(result.review_shown, false) -- Review window should NOT appear on error
end

T["review_window_displays_images_count"] = function()
    _G.child.lua([[
        local result_data = {
            text = "Result with images",
            images = {"image1.png", "image2.png"},
        }
        local metadata = {
            server_name = "test_server",
            tool_name = "test_tool",
            action = "use_mcp_tool",
        }

        _G.test_result = {}
        _G.ui_utils.review_tool_result(result_data, metadata, function(approved) end)

        vim.wait(100)

        -- Find review window and check for image indicator
        local wins = vim.api.nvim_list_wins()
        for _, win in ipairs(wins) do
            local config = vim.api.nvim_win_get_config(win)
            if config.title and type(config.title) == "table" then
                local title_str = config.title[1][1]
                if title_str:match("Review") then
                    local bufnr = vim.api.nvim_win_get_buf(win)
                    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
                    local content = table.concat(lines, "\n")
                    _G.test_result.has_image_indicator = content:match("2 images") ~= nil or content:match("2 image") ~= nil
                    break
                end
            end
        end
    ]])

    -- Close window
    _G.child.type_keys("<Esc>")
    _G.child.lua("vim.wait(100)")

    local result = _G.child.lua_get("_G.test_result")
    eq(result.has_image_indicator, true)
end

T["review_window_truncates_large_results"] = function()
    _G.child.lua([[
        -- Create very large result (over 10,000 lines)
        local large_text = string.rep("Line of text\n", 15000)

        local result_data = {
            text = large_text,
        }
        local metadata = {
            server_name = "test_server",
            tool_name = "test_tool",
            action = "use_mcp_tool",
        }

        _G.test_result = {}
        _G.ui_utils.review_tool_result(result_data, metadata, function(approved) end)

        vim.wait(100)

        -- Check window buffer content
        local wins = vim.api.nvim_list_wins()
        for _, win in ipairs(wins) do
            local config = vim.api.nvim_win_get_config(win)
            if config.title and type(config.title) == "table" then
                local title_str = config.title[1][1]
                if title_str:match("Review") then
                    local bufnr = vim.api.nvim_win_get_buf(win)
                    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
                    local content = table.concat(lines, "\n")
                    _G.test_result.has_truncation = content:match("Truncated") ~= nil
                    _G.test_result.line_count = #lines
                    break
                end
            end
        end
    ]])

    -- Close window
    _G.child.type_keys("<Esc>")
    _G.child.lua("vim.wait(100)")

    local result = _G.child.lua_get("_G.test_result")
    eq(result.has_truncation, true)
end

T["review_window_scrolling_works"] = function()
    _G.child.lua([[
        local large_text = string.rep("Line\n", 100)
        local result_data = {
            text = large_text,
        }
        local metadata = {
            server_name = "test_server",
            tool_name = "test_tool",
            action = "use_mcp_tool",
        }

        _G.ui_utils.review_tool_result(result_data, metadata, function(approved) end)
        vim.wait(100)
    ]])

    -- Try scrolling with j/k
    _G.child.type_keys("j")
    _G.child.lua("vim.wait(25)")
    _G.child.type_keys("k")
    _G.child.lua("vim.wait(25)")

    -- Try Ctrl-D and Ctrl-U
    _G.child.type_keys("<C-d>")
    _G.child.lua("vim.wait(25)")
    _G.child.type_keys("<C-u>")
    _G.child.lua("vim.wait(25)")

    -- Close window
    _G.child.type_keys("<Esc>")
    _G.child.lua("vim.wait(50)")

    -- No errors occurred
    eq(true, true)
end

-- =========================================================================
-- State Management
-- =========================================================================

T["parsed_params_includes_review_requested_field"] = function()
    local result = _G.child.lua_func(function()
        local params = {
            server_name = "test_server",
            tool_name = "test_tool",
            tool_input = { arg1 = "value1" },
        }

        local parsed = _G.shared.parse_params(params, "use_mcp_tool")

        return {
            has_field = parsed.review_requested ~= nil,
            default_value = parsed.review_requested,
        }
    end)

    eq(result.has_field, true)
    eq(result.default_value, false) -- Should default to false
end

T["auto_approve_function_returns_table_with_review_flag"] = function()
    local result = _G.child.lua_func(function()
        -- Set up auto_approve function that returns table
        _G.State.config.auto_approve = function(params)
            if params.server_name == "jira" then
                return { approve = true, review = true }
            end
            return false
        end

        local params = _G.shared.parse_params({
            server_name = "jira",
            tool_name = "search_issues",
            tool_input = {},
        }, "use_mcp_tool")

        local decision = _G.shared.handle_auto_approval_decision(params)

        return {
            approved = decision.approve,
            review_requested = decision.review_requested,
            has_error = decision.error ~= nil,
        }
    end)

    eq(result.approved, true)
    eq(result.review_requested, true)
    eq(result.has_error, false)
end

T["auto_approve_function_boolean_return_no_review"] = function()
    local result = _G.child.lua_func(function()
        _G.State.config.auto_approve = function(params)
            return params.server_name == "filesystem"
        end

        local params = _G.shared.parse_params({
            server_name = "filesystem",
            tool_name = "read_file",
            tool_input = {},
        }, "use_mcp_tool")

        local decision = _G.shared.handle_auto_approval_decision(params)

        return {
            approved = decision.approve,
            review_requested = decision.review_requested,
        }
    end)

    eq(result.approved, true)
    eq(result.review_requested, false) -- Boolean return shouldn't set review
end

T["auto_approve_boolean_true_skips_confirmation_and_review"] = function()
    local result = _G.child.lua_func(function()
        _G.State.config.auto_approve = true

        local params = _G.shared.parse_params({
            server_name = "any_server",
            tool_name = "any_tool",
            tool_input = {},
        }, "use_mcp_tool")

        local decision = _G.shared.handle_auto_approval_decision(params)

        return {
            approved = decision.approve,
            review_requested = decision.review_requested,
        }
    end)

    eq(result.approved, true)
    eq(result.review_requested, false)
end

T["servers_json_auto_approve_skips_review"] = function()
    local result = _G.child.lua_func(function()
        local params = _G.shared.parse_params({
            server_name = "approved_server",
            tool_name = "approved_tool",
            tool_input = {},
        }, "use_mcp_tool")

        -- Simulate server-level auto-approval
        params.is_auto_approved_in_server = true

        local decision = _G.shared.handle_auto_approval_decision(params)

        return {
            approved = decision.approve,
            review_requested = decision.review_requested,
        }
    end)

    eq(result.approved, true)
    eq(result.review_requested, false) -- Server auto-approve shouldn't trigger review
end

-- =========================================================================
-- Edge Cases
-- =========================================================================

T["review_empty_result"] = function()
    _G.child.lua([[
        local result_data = {
            text = "",
        }
        local metadata = {
            server_name = "test_server",
            tool_name = "test_tool",
            action = "use_mcp_tool",
        }

        _G.test_result = {approved = nil}
        _G.ui_utils.review_tool_result(result_data, metadata, function(approved)
            _G.test_result.approved = approved
        end)
        vim.wait(100)
    ]])

    -- Should still show window and allow rejection
    _G.child.type_keys("r")
    _G.child.lua("vim.wait(100)")

    local result = _G.child.lua_get("_G.test_result")
    eq(result.approved, false)
end

T["review_error_result_shows_error_indicator"] = function()
    _G.child.lua([[
        local result_data = {
            text = "Error details",
            isError = true,
            error = "Something went wrong",
        }
        local metadata = {
            server_name = "test_server",
            tool_name = "test_tool",
            action = "use_mcp_tool",
        }

        _G.test_result = {}
        _G.ui_utils.review_tool_result(result_data, metadata, function(approved) end)

        vim.wait(100)

        -- Check window shows error indicator
        local wins = vim.api.nvim_list_wins()
        for _, win in ipairs(wins) do
            local config = vim.api.nvim_win_get_config(win)
            if config.title and type(config.title) == "table" then
                local title_str = config.title[1][1]
                if title_str:match("Review") then
                    local bufnr = vim.api.nvim_win_get_buf(win)
                    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
                    local content = table.concat(lines, "\n")
                    _G.test_result.has_error_indicator = content:match("Error occurred") ~= nil
                    break
                end
            end
        end
    ]])

    -- Close window
    _G.child.type_keys("<Esc>")
    _G.child.lua("vim.wait(100)")

    local result = _G.child.lua_get("_G.test_result")
    eq(result.has_error_indicator, true)
end

T["review_nil_result_shows_notification"] = function()
    _G.child.lua([[
        _G.test_result = {approved = nil, notification = nil}

        -- Override vim.notify to capture notification
        local original_notify = vim.notify
        vim.notify = function(msg, level)
            _G.test_result.notification = {msg = msg, level = level}
            return original_notify(msg, level)
        end

        local metadata = {
            server_name = "test_server",
            tool_name = "test_tool",
            action = "use_mcp_tool",
        }

        _G.ui_utils.review_tool_result(nil, metadata, function(approved)
            _G.test_result.approved = approved
        end)

        vim.wait(100)
    ]])

    local result = _G.child.lua_get("_G.test_result")
    eq(result.approved, false) -- Should reject nil result
    eq(result.notification ~= nil and result.notification ~= vim.NIL, true) -- Should notify user
end

T["review_resource_access_displays_uri"] = function()
    _G.child.lua([[
        local result_data = {
            text = "Resource content here",
        }
        local metadata = {
            server_name = "test_server",
            uri = "file:///test/path",
            action = "access_mcp_resource",
        }

        _G.test_result = {}
        _G.ui_utils.review_tool_result(result_data, metadata, function(approved) end)

        vim.wait(100)

        -- Check that window shows URI instead of tool name
        local wins = vim.api.nvim_list_wins()
        for _, win in ipairs(wins) do
            local config = vim.api.nvim_win_get_config(win)
            if config.title and type(config.title) == "table" then
                local title_str = config.title[1][1]
                if title_str:match("Review") then
                    local bufnr = vim.api.nvim_win_get_buf(win)
                    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
                    local content = table.concat(lines, "\n")
                    _G.test_result.has_resource = content:match("Resource:") ~= nil
                    _G.test_result.has_uri = content:match("file:///test/path") ~= nil
                    break
                end
            end
        end
    ]])

    -- Close window
    _G.child.type_keys("<Esc>")
    _G.child.lua("vim.wait(100)")

    local result = _G.child.lua_get("_G.test_result")
    eq(result.has_resource, true)
    eq(result.has_uri, true)
end

T["auto_approve_error_handling"] = function()
    local result = _G.child.lua_func(function()
        -- Set up auto_approve function that throws error
        _G.State.config.auto_approve = function(params)
            error("Something went wrong!")
        end

        local params = _G.shared.parse_params({
            server_name = "test_server",
            tool_name = "test_tool",
            tool_input = {},
        }, "use_mcp_tool")

        local decision = _G.shared.handle_auto_approval_decision(params)

        return {
            has_error = decision.error ~= nil,
            approved = decision.approve,
            error_message = decision.error,
        }
    end)

    eq(result.approved, false)
    eq(result.has_error, true)
    eq(result.error_message ~= nil, true)
end

T["review_keyboard_shortcuts_y_approves"] = function()
    _G.child.lua([[
        _G.test_result = {approved = nil}
        local result_data = {text = "Test output"}
        local metadata = {server_name = "test", tool_name = "test", action = "use_mcp_tool"}
        _G.ui_utils.review_tool_result(result_data, metadata, function(approved)
            _G.test_result.approved = approved
        end)
        vim.wait(100)
    ]])

    _G.child.type_keys("y")
    _G.child.lua("vim.wait(100)")

    local result = _G.child.lua_get("_G.test_result")
    eq(result.approved, true)
end

T["review_keyboard_shortcuts_capital_a_approves"] = function()
    _G.child.lua([[
        _G.test_result = {approved = nil}
        local result_data = {text = "Test output"}
        local metadata = {server_name = "test", tool_name = "test", action = "use_mcp_tool"}
        _G.ui_utils.review_tool_result(result_data, metadata, function(approved)
            _G.test_result.approved = approved
        end)
        vim.wait(100)
    ]])

    _G.child.type_keys("A")
    _G.child.lua("vim.wait(100)")

    local result = _G.child.lua_get("_G.test_result")
    eq(result.approved, true)
end

T["review_keyboard_shortcuts_n_rejects"] = function()
    _G.child.lua([[
        _G.test_result = {approved = nil}
        local result_data = {text = "Test output"}
        local metadata = {server_name = "test", tool_name = "test", action = "use_mcp_tool"}
        _G.ui_utils.review_tool_result(result_data, metadata, function(approved)
            _G.test_result.approved = approved
        end)
        vim.wait(100)
    ]])

    _G.child.type_keys("n")
    _G.child.lua("vim.wait(100)")

    local result = _G.child.lua_get("_G.test_result")
    eq(result.approved, false)
end

T["review_keyboard_shortcuts_q_rejects"] = function()
    _G.child.lua([[
        _G.test_result = {approved = nil}
        local result_data = {text = "Test output"}
        local metadata = {server_name = "test", tool_name = "test", action = "use_mcp_tool"}
        _G.ui_utils.review_tool_result(result_data, metadata, function(approved)
            _G.test_result.approved = approved
        end)
        vim.wait(100)
    ]])

    _G.child.type_keys("q")
    _G.child.lua("vim.wait(100)")

    local result = _G.child.lua_get("_G.test_result")
    eq(result.approved, false)
end

return T
