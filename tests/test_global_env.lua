-- Tests for global_env functionality
local new_set = MiniTest.new_set
local expect, eq = MiniTest.expect, MiniTest.expect.equality
local helpers = require("tests.helpers")

local T = new_set({
    hooks = {
        pre_case = function()
            -- Clean up environment before each test
            vim.env.MCP_HUB_ENV = nil
            vim.env.TEST_VAR = "test_value"
            vim.env.DBUS_SESSION_BUS_ADDRESS = "/tmp/test_dbus"
        end,
        post_case = function()
            -- Clean up after each test
            vim.env.MCP_HUB_ENV = nil
            vim.env.TEST_VAR = nil
            vim.env.DBUS_SESSION_BUS_ADDRESS = nil
        end,
    },
})

-- Global Env Resolution
T["resolution"] = new_set()

T["resolution"]["resolve_table_format"] = function()
    local hub, state = helpers.setup_plugin({
        global_env = {
            "TEST_VAR",
            "DBUS_SESSION_BUS_ADDRESS",
            CUSTOM_VAR = "custom_value",
        },
    })

    local context = {
        port = 37373,
        is_workspace_mode = false,
        config_files = { "/test/config.json" },
        cwd = "/test",
    }

    local resolved = hub:_resolve_global_env(context)

    -- Check resolved values
    eq(resolved.TEST_VAR, "test_value")
    eq(resolved.DBUS_SESSION_BUS_ADDRESS, "/tmp/test_dbus")
    eq(resolved.CUSTOM_VAR, "custom_value")
end

T["resolution"]["resolve_function_format"] = function()
    local hub, state = helpers.setup_plugin({
        global_env = function(context)
            return {
                "TEST_VAR",
                PORT = tostring(context.port),
                IS_WORKSPACE = context.is_workspace_mode and "true" or "false",
            }
        end,
    })

    local context = {
        port = 40123,
        is_workspace_mode = true,
        config_files = { "/workspace/config.json" },
        cwd = "/workspace",
    }

    local resolved = hub:_resolve_global_env(context)

    -- Check resolved values
    eq(resolved.TEST_VAR, "test_value")
    eq(resolved.PORT, "40123")
    eq(resolved.IS_WORKSPACE, "true")
end

T["resolution"]["nil_global_env"] = function()
    local hub, _ = helpers.setup_plugin({
        global_env = nil,
    })

    local context = { port = 37373 }
    local resolved = hub:_resolve_global_env(context)

    -- Should return empty table without warnings
    eq(vim.deep_equal(resolved, {}), true)
end

return T
