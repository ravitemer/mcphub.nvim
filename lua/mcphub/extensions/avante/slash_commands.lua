local mcphub = require("mcphub")
local shared = require("mcphub.extensions.shared")

local M = {}

---Update avante slash commands with the current MCP prompts.
function M.register()
    local ok, avante_config = pcall(require, "avante.config")
    if not ok then
        return
    end

    local hub = mcphub.get_hub_instance()
    if not hub then
        return
    end
    local prompts = hub:get_prompts()
    local avante_slash_commands = avante_config.slash_commands or {}
    -- remove existing mcp slash commands that start with mcp so that when user disables a server, those prompts are removed
    for i, value in ipairs(avante_slash_commands) do
        local id = value.name or ""
        if id:sub(1, 3) == "mcp" then
            avante_slash_commands[i] = nil
        end
    end
    --add all prompts from MCP servers
    for _, prompt in ipairs(prompts) do
        local server_name = prompt.server_name
        local prompt_name = prompt.name or ""
        local description = prompt.description or ""
        local arguments = prompt.arguments or {}
        if type(description) == "function" then
            local desc_ok, desc = pcall(description, prompt)
            if desc_ok then
                description = desc or ""
            else
                description = "Error in description function: " .. (desc or "")
            end
        end
        if type(arguments) == "function" then
            local args_ok, args = pcall(arguments, prompt)
            if args_ok then
                arguments = args or {}
            else
                vim.notify("Error in arguments function: " .. (args or ""), vim.log.levels.ERROR)
                arguments = {}
            end
        end
        --remove new lines
        description = description:gsub("\n", " ")

        description = prompt_name .. " (" .. description .. ")"
        local slash_command = {
            name = "mcp:" .. server_name .. ":" .. prompt_name,
            description = description,
            callback = function(sidebar, args, cb)
                shared.collect_arguments(arguments, function(values)
                    local response, err = hub:get_prompt(server_name, prompt_name, values, {
                        caller = {
                            type = "avante",
                            avante = sidebar,
                            meta = {
                                is_within_slash_command = true,
                            },
                        },
                        parse_response = true,
                    })
                    if not response then
                        if err then
                            vim.notify("Error in slash command: " .. err, vim.log.levels.ERROR)
                            vim.notify("Prompt cancelled", vim.log.levels.INFO)
                        end
                        return
                    end
                    local messages = response.messages or {}
                    local text_messages = {}
                    for i, message in ipairs(messages) do
                        local output = message.output
                        if output.text and output.text ~= "" then
                            if i == #messages and message.role == "user" then
                                sidebar:set_input_value(output.text)
                            else
                                table.insert(text_messages, {
                                    role = message.role,
                                    content = output.text,
                                })
                            end
                        end
                    end
                    sidebar:add_chat_history(text_messages, { visible = true })
                    vim.notify(
                        string.format(
                            "%s message%s added successfully",
                            #text_messages,
                            #text_messages == 1 and "" or "s"
                        ),
                        vim.log.levels.INFO
                    )
                    if cb then
                        cb()
                    end
                end)
            end,
        }
        table.insert(avante_slash_commands, slash_command)
    end
end

---Add slash commands to Avante for all active MCP servers
function M.setup()
    ---Immediately register slash commands if enabled
    M.register()
    --setup event listeners to update slash commands
    mcphub.on({ "servers_updated", "prompt_list_changed" }, M.register)
end

return M
