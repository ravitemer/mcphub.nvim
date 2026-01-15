local M = {}
local mcphub = require("mcphub")

local shared = require("mcphub.extensions.shared")

function M.register()
    local config = require("codecompanion.config")
    local hub = mcphub.get_hub_instance()
    if not hub then
        return
    end

    local prompts = hub:get_prompts()
    local slash_commands = config.interactions.chat.slash_commands

    -- Remove existing MCP slash commands
    for key, value in pairs(slash_commands) do
        local id = value.id or ""
        if id:sub(1, 3) == "mcp" then
            slash_commands[key] = nil
        end
    end

    -- Add current prompts as slash commands
    for _, prompt in ipairs(prompts) do
        local server_name = prompt.server_name
        local prompt_name = prompt.name or ""
        local description = prompt.description or ""
        description = description:gsub("\n", " ")
        description = prompt_name .. " (" .. description .. ")"

        local arguments = prompt.arguments or {}
        if type(arguments) == "function" then
            local ok, args = pcall(arguments, prompt)
            if ok then
                arguments = args or {}
            else
                vim.notify("Error in arguments function: " .. (args or ""), vim.log.levels.ERROR)
                arguments = {}
            end
        end

        slash_commands["mcp:" .. prompt_name] = {
            id = "mcp" .. server_name .. prompt_name,
            description = description,
            callback = function(self)
                shared.collect_arguments(arguments, function(values)
                    -- Sync call - blocks UI (can't use async in slash_commands yet)
                    local response, err = hub:get_prompt(server_name, prompt_name, values, {
                        caller = {
                            type = "codecompanion",
                            codecompanion = self,
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
                    local text_messages = 0

                    for i, message in ipairs(messages) do
                        local output = message.output
                        local mapped_role = message.role == "assistant" and config.constants.LLM_ROLE
                            or message.role == "system" and config.constants.SYSTEM_ROLE
                            or config.constants.USER_ROLE

                        if output.text and output.text ~= "" then
                            text_messages = text_messages + 1
                            -- If last message is from user, add it to chat buffer
                            if i == #messages and mapped_role == config.constants.USER_ROLE then
                                self:add_buf_message({
                                    role = mapped_role,
                                    content = output.text,
                                })
                            else
                                self:add_message({
                                    role = mapped_role,
                                    content = output.text,
                                })
                            end
                        end

                        -- Handle images
                        if output.images and #output.images > 0 then
                            local helpers = require("codecompanion.interactions.chat.helpers")
                            for _, image in ipairs(output.images) do
                                local id = string.format("mcp-%s", os.time())
                                helpers.add_image(self, {
                                    id = id,
                                    base64 = image.data,
                                    mimetype = image.mimeType,
                                }, { role = mapped_role })
                            end
                        end
                    end

                    vim.notify(
                        string.format(
                            "%s message%s added successfully",
                            text_messages,
                            text_messages == 1 and "" or "s"
                        ),
                        vim.log.levels.INFO
                    )
                end)
            end,
        }
    end
end

--- Setup MCP prompts as CodeCompanion slash commands
---@param opts MCPHub.Extensions.CodeCompanionConfig
function M.setup(opts)
    if not opts.make_slash_commands then
        return
    end

    vim.schedule(function()
        M.register()
    end)
    mcphub.on(
        { "servers_updated", "prompt_list_changed" },
        vim.schedule_wrap(function()
            M.register()
        end)
    )
end

return M
