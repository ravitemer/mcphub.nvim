local M = {}
local mcphub = require("mcphub")

---@param tbl table|nil
local function cleanup_mcp_items(tbl)
    if type(tbl) ~= "table" then
        return
    end

    for key, value in pairs(tbl) do
        if type(value) == "table" then
            local id = value.id or ""
            if id:sub(1, 3) == "mcp" then
                tbl[key] = nil
            end
        end
    end
end

---@param hub MCPHub.Instance
---@param server_name string
---@param uri string
---@return function
local function make_resource_callback(hub, server_name, uri)
    return function(self)
        -- Sync call - blocks UI (can't use async in variables/editor_context yet)
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
            local helpers = require("codecompanion.interactions.chat.helpers")
            local chat = self and (self.Chat or self)

            if chat then
                for _, image in ipairs(result.images) do
                    local id = string.format("mcp-%s", os.time())
                    helpers.add_image(chat, {
                        id = id,
                        base64 = image.data,
                        mimetype = image.mimeType,
                    })
                end
            end
        end

        return result.text
    end
end

---@param resources table
---@param target table
---@param hub MCPHub.Instance
---@return string[]
local function register_legacy_variables(resources, target, hub)
    cleanup_mcp_items(target)

    local added_resources = {}

    for _, resource in ipairs(resources) do
        local server_name = resource.server_name
        local uri = resource.uri
        local resource_name = resource.name or uri
        local description = resource.description or ""
        description = description:gsub("\n", " ")
        description = resource_name .. " (" .. description .. ")"

        local var_id = "mcp:" .. uri
        target[var_id] = {
            id = "mcp" .. server_name .. uri,
            description = description,
            hide_in_help_window = true,
            callback = make_resource_callback(hub, server_name, uri),
        }

        table.insert(added_resources, var_id)
    end

    return added_resources
end

---@param resources table
---@param target table
---@param hub MCPHub.Instance
---@return string[]
local function register_editor_context(resources, target, hub)
    cleanup_mcp_items(target)

    local added_resources = {}

    for _, resource in ipairs(resources) do
        local server_name = resource.server_name
        local uri = resource.uri
        local resource_name = resource.name or uri
        local description = resource.description or ""
        description = description:gsub("\n", " ")
        description = resource_name .. " (" .. description .. ")"

        local var_id = "mcp:" .. uri
        target[var_id] = {
            id = "mcp" .. server_name .. uri,
            description = description,
            hide_in_help_window = true,
            callback = make_resource_callback(hub, server_name, uri),
        }

        table.insert(added_resources, var_id)
    end

    return added_resources
end

---@param config table
---@return string|nil, table|nil
local function get_backend(config)
    local interactions = config.interactions or {}
    local chat = interactions.chat or {}
    local shared = interactions.shared or {}

    if type(chat.variables) == "table" then
        return "variables", chat.variables
    end

    if type(shared.editor_context) == "table" then
        return "editor_context", shared.editor_context
    end

    if type(chat.editor_context) == "table" then
        return "editor_context", chat.editor_context
    end

    return nil, nil
end

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

    local backend, target = get_backend(config)
    if not backend or not target then
        vim.notify(
            "MCPHub: no compatible CodeCompanion resource registration backend found",
            vim.log.levels.WARN,
            { title = "MCPHub" }
        )
        return
    end

    local added_resources = {}

    if backend == "variables" then
        added_resources = register_legacy_variables(resources, target, hub)
    elseif backend == "editor_context" then
        added_resources = register_editor_context(resources, target, hub)
    end

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
