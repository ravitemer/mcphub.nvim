-- Tests for EditUI - Interactive Editing Session
local new_set = MiniTest.new_set
local expect, eq = MiniTest.expect, MiniTest.expect.equality
local Helpers = require("tests.helpers")

local T = new_set({
    hooks = {
        pre_case = function()
            _G.child = Helpers.new_child_neovim()
            _G.child.setup()
        end,
        post_case = function()
            if _G.child then
                _G.child.stop()
                _G.child = nil
                vim.fn.delete("test_file.lua")
            end
        end,
    },
})

-- Helper to start an interactive session in the child Neovim
local function start_session(file_content, diff_content)
    -- Set initial file content in the child
    _G.child.set_lines(file_content)
    _G.child.cmd("w! test_file.lua")

    -- Use lua_func to run the session inside the child process
    return _G.child.lua_func(function(file_content, diff_content)
        local EditSession = require("mcphub.native.neovim.files.edit_file.edit_session")
        _G.session = EditSession.new("test_file.lua", diff_content)

        local success_data, error_data
        _G.session:start({
            interactive = true,
            on_success = function(summary)
                success_data = summary
            end,
            on_error = function(err)
                error_data = err
            end,
        })

        -- Wait for UI to initialize
        vim.wait(50)

        return { success_data = success_data, error_data = error_data }
    end, file_content, diff_content)
end

-- =========================================================================
-- Test Scenarios
-- =========================================================================

T["basic_setup"] = function()
    -- Simple test to verify the basic setup works
    local file_content = "print('hello world')"

    _G.child.set_lines({ file_content })
    local lines = _G.child.get_lines()

    eq(lines[1], file_content)
end

T["simple_change_acceptance"] = function()
    local file_content = 'function test()\n    return "old value"\nend'

    local diff_content = '<<<<<<< SEARCH\n    return "old value"\n=======\n    return "new value"\n>>>>>>> REPLACE'

    _G.child.set_lines(vim.split(file_content, "\n"))
    _G.child.cmd("w! test_file.lua")

    -- Start the session inside child
    _G.child.lua_func(function(diff_content)
        local EditSession = require("mcphub.native.neovim.files.edit_file.edit_session")
        _G.session = EditSession.new("test_file.lua", diff_content)

        _G.session:start({
            interactive = true,
            on_success = function(summary) end,
            on_error = function(err) end,
        })

        vim.wait(50) -- Give UI time to initialize
    end, diff_content)

    -- Now simulate user accepting the change by pressing '.'
    _G.child.type_keys(".")

    -- Wait for the change to be processed
    _G.child.lua("vim.wait(100)")

    -- Get the final result
    local final_result = _G.child.lua_func(function()
        return {
            completed = _G.session and _G.session.ui and _G.session.ui.state and _G.session.ui.state.has_completed
                or false,
            current_lines = vim.api.nvim_buf_get_lines(0, 0, -1, false),
        }
    end)

    -- Verify the change was applied and session completed
    eq(final_result.completed, true)
    eq(final_result.current_lines[2], '    return "new value"')
end

T["simple_change_rejection"] = function()
    local file_content = 'function test()\n    return "original value"\nend'

    -- Build diff content
    local diff_content =
        '<<<<<<< SEARCH\n    return "original value"\n=======\n    return "changed value"\n>>>>>>> REPLACE'

    -- Setup the file in child
    _G.child.set_lines(vim.split(file_content, "\n"))
    _G.child.cmd("w! test_file.lua")

    -- Start the session inside child
    _G.child.lua_func(function(diff_content)
        local EditSession = require("mcphub.native.neovim.files.edit_file.edit_session")
        _G.session = EditSession.new("test_file.lua", diff_content)

        _G.session:start({
            interactive = true,
            on_success = function(summary) end,
            on_error = function(err) end,
        })

        vim.wait(50) -- Give UI time to initialize
    end, diff_content)

    -- Now simulate user rejecting the change by pressing ','
    _G.child.type_keys(",")

    -- Wait for the change to be processed
    _G.child.lua("vim.wait(100)")

    -- Get the final result
    local final_result = _G.child.lua_func(function()
        return {
            completed = _G.session and _G.session.ui and _G.session.ui.state and _G.session.ui.state.has_completed
                or false,
            current_lines = vim.api.nvim_buf_get_lines(0, 0, -1, false),
        }
    end)

    -- Verify the change was rejected (reverted to original) and session completed
    eq(final_result.completed, true)
    eq(final_result.current_lines[2], '    return "original value"')
end

T["multiple_hunks_mixed_decisions"] = function()
    local file_content =
        'function first()\n    return "old1"\nend\n\nfunction second()\n    return "old2"\nend\n\nfunction third()\n    return "old3"\nend'

    -- Setup the file in child
    _G.child.set_lines(vim.split(file_content, "\n"))
    _G.child.cmd("w! test_file.lua")

    -- Start the session with multiple changes
    _G.child.lua_func(function()
        local diff_parts = {
            "<<<<<<< SEARCH",
            '    return "old1"',
            "=======",
            '    return "new1"',
            ">>>>>>> REPLACE",
            "",
            "<<<<<<< SEARCH",
            '    return "old2"',
            "=======",
            '    return "new2"',
            ">>>>>>> REPLACE",
            "",
            "<<<<<<< SEARCH",
            '    return "old3"',
            "=======",
            '    return "new3"',
            ">>>>>>> REPLACE",
        }
        local diff_content = table.concat(diff_parts, "\n")

        local EditSession = require("mcphub.native.neovim.files.edit_file.edit_session")
        _G.session = EditSession.new("test_file.lua", diff_content)

        _G.session:start({
            interactive = true,
            on_success = function(summary) end,
            on_error = function(err) end,
        })

        vim.wait(50)
    end)

    -- Accept first hunk (.)
    _G.child.type_keys(".")
    _G.child.lua("vim.wait(50)")

    -- Reject second hunk (,)
    _G.child.type_keys(",")
    _G.child.lua("vim.wait(50)")

    -- Accept third hunk (.)
    _G.child.type_keys(".")
    _G.child.lua("vim.wait(100)")

    -- Get the final result
    local final_result = _G.child.lua_func(function()
        return {
            completed = _G.session and _G.session.ui and _G.session.ui.state and _G.session.ui.state.has_completed
                or false,
            current_lines = vim.api.nvim_buf_get_lines(0, 0, -1, false),
        }
    end)

    -- Verify mixed results: first and third accepted, second rejected
    eq(final_result.completed, true)
    eq(final_result.current_lines[2], '    return "new1"') -- First accepted
    eq(final_result.current_lines[6], '    return "old2"') -- Second rejected (reverted)
    eq(final_result.current_lines[10], '    return "new3"') -- Third accepted
end

T["accept_all_functionality"] = function()
    local file_content = 'function first()\n    return "old1"\nend\n\nfunction second()\n    return "old2"\nend'

    -- Setup the file in child
    _G.child.set_lines(vim.split(file_content, "\n"))
    _G.child.cmd("w! test_file.lua")

    -- Start the session with multiple changes
    _G.child.lua_func(function()
        local diff_parts = {
            "<<<<<<< SEARCH",
            '    return "old1"',
            "=======",
            '    return "new1"',
            ">>>>>>> REPLACE",
            "",
            "<<<<<<< SEARCH",
            '    return "old2"',
            "=======",
            '    return "new2"',
            ">>>>>>> REPLACE",
        }
        local diff_content = table.concat(diff_parts, "\n")

        local EditSession = require("mcphub.native.neovim.files.edit_file.edit_session")
        _G.session = EditSession.new("test_file.lua", diff_content)

        _G.session:start({
            interactive = true,
            on_success = function(summary) end,
            on_error = function(err) end,
        })

        vim.wait(50)
    end)

    -- Use "accept all" functionality (ga)
    _G.child.type_keys("ga")
    _G.child.lua("vim.wait(100)")

    -- Get the final result
    local final_result = _G.child.lua_func(function()
        return {
            completed = _G.session and _G.session.ui and _G.session.ui.state and _G.session.ui.state.has_completed
                or false,
            current_lines = vim.api.nvim_buf_get_lines(0, 0, -1, false),
        }
    end)

    -- Verify all changes were accepted
    eq(final_result.completed, true)
    eq(final_result.current_lines[2], '    return "new1"') -- First accepted
    eq(final_result.current_lines[6], '    return "new2"') -- Second accepted
end

T["reject_all_functionality"] = function()
    local file_content =
        'function first()\n    return "original1"\nend\n\nfunction second()\n    return "original2"\nend'

    -- Setup the file in child
    _G.child.set_lines(vim.split(file_content, "\n"))
    _G.child.cmd("w! test_file.lua")

    -- Start the session with multiple changes
    _G.child.lua_func(function()
        local diff_parts = {
            "<<<<<<< SEARCH",
            '    return "original1"',
            "=======",
            '    return "changed1"',
            ">>>>>>> REPLACE",
            "",
            "<<<<<<< SEARCH",
            '    return "original2"',
            "=======",
            '    return "changed2"',
            ">>>>>>> REPLACE",
        }
        local diff_content = table.concat(diff_parts, "\n")

        local EditSession = require("mcphub.native.neovim.files.edit_file.edit_session")
        _G.session = EditSession.new("test_file.lua", diff_content)

        _G.session:start({
            interactive = true,
            on_success = function(summary) end,
            on_error = function(err) end,
        })

        vim.wait(50)
    end)

    -- Use "reject all" functionality (gr)
    _G.child.type_keys("gr")

    -- Wait a bit longer for the rejection to complete
    vim.wait(200)

    -- Get the final result
    local final_result = _G.child.lua_func(function()
        return {
            completed = _G.session and _G.session.ui and _G.session.ui.state and _G.session.ui.state.has_completed
                or false,
            current_lines = vim.api.nvim_buf_get_lines(0, 0, -1, false),
        }
    end)

    -- Verify all changes were rejected (back to original)
    eq(final_result.completed, true)
    eq(final_result.current_lines[2], '    return "original1"') -- First reverted
    eq(final_result.current_lines[6], '    return "original2"') -- Second reverted
end

T["navigation_between_hunks"] = function()
    local file_content =
        'function first()\n    return "val1"\nend\n\nfunction second()\n    return "val2"\nend\n\nfunction third()\n    return "val3"\nend'

    -- Setup the file in child
    _G.child.set_lines(vim.split(file_content, "\n"))
    _G.child.cmd("w! test_file.lua")

    -- Start the session with multiple changes
    _G.child.lua_func(function()
        local diff_parts = {
            "<<<<<<< SEARCH",
            '    return "val1"',
            "=======",
            '    return "new1"',
            ">>>>>>> REPLACE",
            "",
            "<<<<<<< SEARCH",
            '    return "val2"',
            "=======",
            '    return "new2"',
            ">>>>>>> REPLACE",
            "",
            "<<<<<<< SEARCH",
            '    return "val3"',
            "=======",
            '    return "new3"',
            ">>>>>>> REPLACE",
        }
        local diff_content = table.concat(diff_parts, "\n")

        local EditSession = require("mcphub.native.neovim.files.edit_file.edit_session")
        _G.session = EditSession.new("test_file.lua", diff_content)

        _G.session:start({
            interactive = true,
            on_success = function(summary) end,
            on_error = function(err) end,
        })

        vim.wait(50)
    end)

    -- Navigate: next (n), next (n), previous (p), accept current (.)
    _G.child.type_keys("n") -- Go to second hunk
    _G.child.lua("vim.wait(25)")

    _G.child.type_keys("n") -- Go to third hunk
    _G.child.lua("vim.wait(25)")

    _G.child.type_keys("p") -- Go back to second hunk
    _G.child.lua("vim.wait(25)")

    _G.child.type_keys(".") -- Accept second hunk
    _G.child.lua("vim.wait(50)")

    -- Accept remaining hunks
    _G.child.type_keys("ga")
    _G.child.lua("vim.wait(100)")

    -- Get the final result
    local final_result = _G.child.lua_func(function()
        return {
            completed = _G.session and _G.session.ui and _G.session.ui.state and _G.session.ui.state.has_completed
                or false,
            current_lines = vim.api.nvim_buf_get_lines(0, 0, -1, false),
        }
    end)

    -- Verify all changes were applied (navigation didn't break anything)
    eq(final_result.completed, true)
    eq(final_result.current_lines[2], '    return "new1"')
    eq(final_result.current_lines[6], '    return "new2"')
    eq(final_result.current_lines[10], '    return "new3"')
end

T["non_interactive_mode"] = function()
    local file_content = 'function test()\n    return "auto_value"\nend'

    -- Setup the file in child
    _G.child.set_lines(vim.split(file_content, "\n"))
    _G.child.cmd("w! test_file.lua")

    -- Start session in non-interactive mode
    _G.child.lua_func(function()
        local diff_content =
            '<<<<<<< SEARCH\n    return "auto_value"\n=======\n    return "auto_changed"\n>>>>>>> REPLACE'

        local EditSession = require("mcphub.native.neovim.files.edit_file.edit_session")
        _G.session = EditSession.new("test_file.lua", diff_content)

        _G.session:start({
            interactive = false, -- Non-interactive mode
            on_success = function(summary) end,
            on_error = function(err) end,
        })

        -- Wait for completion
        vim.wait(100)
    end)

    -- Get the result after non-interactive completion
    local final_result = _G.child.lua_func(function()
        return {
            current_lines = vim.api.nvim_buf_get_lines(0, 0, -1, false),
        }
    end)

    -- Verify auto-approval worked - changes should be applied automatically
    eq(final_result.current_lines[2], '    return "auto_changed"')
end

T["deletion_hunk_handling"] = function()
    local file_content =
        'function keep()\n    return "keep"\nend\n\nfunction delete_me()\n    return "delete"\nend\n\nfunction also_keep()\n    return "keep"\nend'

    -- Setup the file in child
    _G.child.set_lines(vim.split(file_content, "\n"))
    _G.child.cmd("w! test_file.lua")

    -- Start session with deletion
    _G.child.lua_func(function()
        local diff_parts = {
            "<<<<<<< SEARCH",
            "function delete_me()",
            '    return "delete"',
            "end",
            "",
            "=======",
            ">>>>>>> REPLACE",
        }
        local diff_content = table.concat(diff_parts, "\n")

        local EditSession = require("mcphub.native.neovim.files.edit_file.edit_session")
        _G.session = EditSession.new("test_file.lua", diff_content)

        _G.session:start({
            interactive = true,
            on_success = function(summary) end,
            on_error = function(err) end,
        })

        vim.wait(50)
    end)

    -- Accept the deletion
    _G.child.type_keys(".")
    _G.child.lua("vim.wait(100)")

    -- Get the final result
    local final_result = _G.child.lua_func(function()
        return {
            completed = _G.session and _G.session.ui and _G.session.ui.state and _G.session.ui.state.has_completed
                or false,
            current_lines = vim.api.nvim_buf_get_lines(0, 0, -1, false),
        }
    end)

    -- Verify the function was deleted
    eq(final_result.completed, true)
    -- Should only have the keep functions, not delete_me
    local content = table.concat(final_result.current_lines, "\n")
    expect.equality(content:match("delete_me") == nil, true)
    expect.equality(content:match("keep") ~= nil, true)
end

T["deletion_hunk_rejection"] = function()
    local file_content = 'function important()\n    return "important"\nend'

    -- Setup the file in child
    _G.child.set_lines(vim.split(file_content, "\n"))
    _G.child.cmd("w! test_file.lua")

    -- Start session with deletion attempt
    _G.child.lua_func(function()
        local diff_content =
            '<<<<<<< SEARCH\nfunction important()\n    return "important"\nend\n=======\n>>>>>>> REPLACE'

        local EditSession = require("mcphub.native.neovim.files.edit_file.edit_session")
        _G.session = EditSession.new("test_file.lua", diff_content)

        _G.session:start({
            interactive = true,
            on_success = function(summary) end,
            on_error = function(err) end,
        })

        vim.wait(50)
    end)

    -- Reject the deletion
    _G.child.type_keys(",")
    _G.child.lua("vim.wait(100)")

    -- Get the final result
    local final_result = _G.child.lua_func(function()
        return {
            completed = _G.session and _G.session.ui and _G.session.ui.state and _G.session.ui.state.has_completed
                or false,
            current_lines = vim.api.nvim_buf_get_lines(0, 0, -1, false),
        }
    end)

    -- Verify the function was preserved
    eq(final_result.completed, true)
    eq(final_result.current_lines[1], "function important()")
    eq(final_result.current_lines[2], '    return "important"')
end

T["addition_hunk_handling"] = function()
    local file_content = "-- Existing code\nlocal x = 1"

    -- Setup the file in child
    _G.child.set_lines(vim.split(file_content, "\n"))
    _G.child.cmd("w! test_file.lua")

    -- Start session with addition
    _G.child.lua_func(function()
        local diff_content =
            '<<<<<<< SEARCH\nlocal x = 1\n=======\nlocal x = 1\n\n-- New function added\nfunction new_function()\n    return "new"\nend\n>>>>>>> REPLACE'

        local EditSession = require("mcphub.native.neovim.files.edit_file.edit_session")
        _G.session = EditSession.new("test_file.lua", diff_content)

        _G.session:start({
            interactive = true,
            on_success = function(summary) end,
            on_error = function(err) end,
        })

        vim.wait(50)
    end)

    -- Accept the addition
    _G.child.type_keys(".")
    _G.child.lua("vim.wait(100)")

    -- Get the final result
    local final_result = _G.child.lua_func(function()
        return {
            completed = _G.session and _G.session.ui and _G.session.ui.state and _G.session.ui.state.has_completed
                or false,
            current_lines = vim.api.nvim_buf_get_lines(0, 0, -1, false),
        }
    end)

    -- Verify the addition was applied
    eq(final_result.completed, true)
    local content = table.concat(final_result.current_lines, "\n")
    expect.equality(content:match("new_function") ~= nil, true)
    expect.equality(content:match("-- New function added") ~= nil, true)
end

T["session_completion_via_save"] = function()
    local file_content = 'function test()\n    return "save_test"\nend'

    -- Setup the file in child
    _G.child.set_lines(vim.split(file_content, "\n"))
    _G.child.cmd("w! test_file.lua")

    -- Start session
    _G.child.lua_func(function()
        local diff_content =
            '<<<<<<< SEARCH\n    return "save_test"\n=======\n    return "save_changed"\n>>>>>>> REPLACE'

        local EditSession = require("mcphub.native.neovim.files.edit_file.edit_session")
        _G.session = EditSession.new("test_file.lua", diff_content)

        _G.session:start({
            interactive = true,
            on_success = function(summary) end,
            on_error = function(err) end,
        })

        vim.wait(50)
    end)

    -- Instead of using keybindings, save the file to trigger completion
    _G.child.cmd("w")
    _G.child.lua("vim.wait(100)")

    -- Get the final result
    local final_result = _G.child.lua_func(function()
        return {
            completed = _G.session and _G.session.ui and _G.session.ui.state and _G.session.ui.state.has_completed
                or false,
            current_lines = vim.api.nvim_buf_get_lines(0, 0, -1, false),
        }
    end)

    -- Verify session completed via save and changes were applied
    eq(final_result.completed, true)
    eq(final_result.current_lines[2], '    return "save_changed"')
end

return T
