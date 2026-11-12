local new_set = MiniTest.new_set
local eq = MiniTest.expect.equality

local T = new_set()

local function run_output_handler(version, show_result_in_chat, is_error)
    local previous_cc = package.loaded["codecompanion"]
    local previous_config = package.loaded["codecompanion.config"]
    package.loaded["codecompanion"] = {
        version = function()
            return version
        end,
    }
    package.loaded["codecompanion.config"] = { constants = { LLM_ROLE = "llm" } }

    local calls = {}
    local chat = {
        MESSAGE_TYPES = { TOOL_MESSAGE = "tool_message" },
        add_tool_output = function(_, ...)
            table.insert(calls, { method = "add_tool_output", args = { ... } })
        end,
        add_buf_message = function(_, ...)
            table.insert(calls, { method = "add_buf_message", args = { ... } })
        end,
    }
    local tool = { name = "use_mcp_tool" }
    local handlers = require("mcphub.extensions.codecompanion.core").create_output_handlers("use_mcp_tool", true, {
        show_result_in_chat = show_result_in_chat,
    })
    if is_error then
        handlers.error(tool, { "MCP error" }, { tools = { chat = chat } })
    else
        handlers.success(tool, { { text = "MCP result" } }, { tools = { chat = chat } })
    end

    package.loaded["codecompanion"] = previous_cc
    package.loaded["codecompanion.config"] = previous_config
    return calls, tool
end

T["v20 sends structured tool output and visible results"] = function()
    local calls, tool = run_output_handler("20.1.0", true, false)
    eq(#calls, 2)
    eq(calls[1].method, "add_tool_output")
    eq(calls[1].args[1], tool)
    eq(type(calls[1].args[2]), "table")
    eq(calls[1].args[2].content:find("MCP result", 1, true) ~= nil, true)
    eq(calls[2].method, "add_buf_message")
    eq(calls[2].args[1].role, "llm")
    eq(calls[2].args[2].type, "tool_message")
end

T["v20 hides successful output but shows errors"] = function()
    local success_calls = run_output_handler("20.1.0", false, false)
    eq(#success_calls, 1)
    local error_calls = run_output_handler("20.1.0", false, true)
    eq(#error_calls, 2)
    eq(error_calls[2].args[1].content:find("MCP error", 1, true) ~= nil, true)
end

T["v19 retains positional tool output"] = function()
    local calls, tool = run_output_handler("19.27.0", true, false)
    eq(#calls, 1)
    eq(calls[1].args[1], tool)
    eq(type(calls[1].args[2]), "string")
    eq(type(calls[1].args[3]), "string")
end

T["chat input highlights newly registered MCP items"] = function()
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "@{demo_server} #{mcp:hello}" })
    vim.bo[bufnr].filetype = "codecompanion_chat_input"
    vim.bo[bufnr].syntax = "ON"

    require("mcphub.extensions.codecompanion.tools").update_syntax_highlighting({
        demo_server = { tool_names = { "demo_server__echo" } },
    })
    require("mcphub.extensions.codecompanion.variables").update_variable_syntax({ "mcp:hello" })
    vim.wait(100)

    vim.api.nvim_buf_call(bufnr, function()
        eq(vim.fn.synIDattr(vim.fn.synID(1, 3, 1), "name"), "CodeCompanionChatToolGroup")
        eq(vim.fn.synIDattr(vim.fn.synID(1, 19, 1), "name"), "CodeCompanionChatEditorContext")
    end)
    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["MCP slash command writes the final user message to the prompt"] = function()
    local mcphub = require("mcphub")
    local previous_get_hub_instance = mcphub.get_hub_instance
    local previous_config = package.loaded["codecompanion.config"]
    local config = {
        constants = { LLM_ROLE = "llm", SYSTEM_ROLE = "system", USER_ROLE = "user" },
        interactions = { chat = { slash_commands = {} } },
    }
    package.loaded["codecompanion.config"] = config
    mcphub.get_hub_instance = function()
        return {
            get_prompts = function()
                return { { server_name = "demo", name = "hello", arguments = {} } }
            end,
            get_prompt = function()
                return { messages = { { role = "user", output = { text = "MCP prompt text" } } } }
            end,
        }
    end

    require("mcphub.extensions.codecompanion.slash_commands").register()
    local prompt_text
    local chat = {
        prompt = {
            add = function(_, args)
                prompt_text = args.content
            end,
        },
        add_buf_message = function()
            error("Final user message went to the conversation buffer")
        end,
    }
    config.interactions.chat.slash_commands["mcp:hello"].callback(chat)

    mcphub.get_hub_instance = previous_get_hub_instance
    package.loaded["codecompanion.config"] = previous_config
    eq(prompt_text, "MCP prompt text")
end

return T
