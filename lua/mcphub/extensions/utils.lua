local M = {}
function M.setup_codecompanion_variables(enabled)
    if not enabled then
        return
    end
    local mcphub = require("mcphub")
    --setup event listners to update variables, tools etc
    mcphub.on("servers_updated", function(opts)
        local hub = opts.hub
        local resources = hub:get_resources()
        local ok, config = pcall(require, "codecompanion.config")
        if not ok then
            return
        end
        local cc_variables = config.strategies.chat.variables
        -- remove existing mcp variables that start with mcp
        for key, value in pairs(cc_variables) do
            local id = value.id or ""
            if id:sub(1, 3) == "mcp" then
                cc_variables[key] = nil
            end
        end
        for _, resource in ipairs(resources) do
            local server_name = resource.server_name
            local uri = resource.uri
            local resource_name = resource.name or uri
            local description = resource.description or ""
            if type(description) == "function" then
                local ok, desc = pcall(description, resource)
                if ok then
                    description = desc or ""
                else
                    description = "Error in description function: " .. (desc or "")
                end
            end
            description = resource_name .. "\n\n" .. description
            cc_variables[uri] = {
                id = "mcp" .. server_name .. uri,
                description = description,
                callback = function(self)
                    -- this is sync and will block the UI (can't use async in variables yet)
                    local response = hub:access_resource(server_name, uri, {
                        caller = {
                            type = "codecompanion",
                            codecompanion = self,
                        },
                        parse_response = true,
                    })
                    return response.text
                end,
            }
        end
    end)
end

function M.setup_codecompanion_tools(enabled)
    if not enabled then
        return
    end
    --INFO:Individual tools might be an overkill
end

return M
