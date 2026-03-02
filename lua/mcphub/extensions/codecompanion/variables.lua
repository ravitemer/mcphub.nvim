local M = {}
local mcphub = require("mcphub")

---@param opts MCPHub.Extensions.CodeCompanionConfig
function M.register(opts)
    local hub = mcphub.get_hub_instance()
    if not hub then
        return
    end

    local resources = hub:get_resources()
    local ok, config = pcall(require, "codecompanion.config")
    if not ok then
        return
    end

    local cc_editor_context = config.interactions.chat.editor_context

    -- Remove existing MCP editor context entries
    for key, _ in pairs(cc_editor_context) do
        if type(key) == "string" and key:sub(1, 4) == "mcp:" then
            cc_editor_context[key] = nil
        end
    end

    local added_resources = {}
    -- Add current resources as editor context
    for _, resource in ipairs(resources) do
        local server_name = resource.server_name
        local uri = resource.uri
        local resource_name = resource.name or uri
        local description = resource.description or ""
        description = description:gsub("\n", " ")
        description = resource_name .. " (" .. description .. ")"
        local var_id = "mcp:" .. uri
        cc_editor_context[var_id] = {
            description = description,
            hide_in_help_window = true,
            callback = function(self)
                -- Sync call - blocks UI (can't use async in editor context yet)
                local result = hub:access_resource(server_name, uri, {
                    caller = {
                        type = "codecompanion",
                        codecompanion = self,
                        meta = {
                            is_within_variable = true,
                        },
                    },
                    parse_response = true,
                })

                if not result then
                    return string.format("Accessing resource failed: %s", uri)
                end

                -- Handle images
                if result.images and #result.images > 0 then
                    for _, image in ipairs(result.images) do
                        local id = string.format("mcp-%s", os.time())
                        self.Chat:add_image_message({
                            id = id,
                            base64 = image.data,
                            mimetype = image.mimeType,
                        })
                    end
                end

                return result.text
            end,
        }
        table.insert(added_resources, var_id)
    end

    -- Update syntax highlighting for editor context
    M.update_variable_syntax(added_resources)
end
-- Setup MCP resources as CodeCompanion variables
---@param opts MCPHub.Extensions.CodeCompanionConfig
function M.setup(opts)
    if not opts.make_vars then
        return
    end
    vim.schedule(function()
        M.register(opts)
    end)
    mcphub.on(
        { "servers_updated", "resource_list_changed" },
        vim.schedule_wrap(function()
            M.register(opts)
        end)
    )
end

--- Update syntax highlighting for variables
---@param resources string[]
function M.update_variable_syntax(resources)
    vim.schedule(function()
        for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
            if vim.api.nvim_buf_is_valid(bufnr) and vim.bo[bufnr].filetype == "codecompanion" then
                vim.api.nvim_buf_call(bufnr, function()
                    for _, resource in ipairs(resources) do
                        vim.cmd.syntax('match CodeCompanionChatVariable "#{' .. resource .. '}"')
                        vim.cmd.syntax('match CodeCompanionChatVariable "#{' .. resource .. '}{[^}]*}"')
                    end
                end)
            end
        end
    end)
end

return M
