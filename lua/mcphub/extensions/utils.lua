local M = {}
function M.setup_codecompanion_variables(enabled)
    if not enabled then
        return
    end
    local mcphub = require("mcphub")
    --setup event listners to update variables, tools etc
    mcphub.on({ "servers_updated", "resource_list_changed" }, function(_)
        local hub = mcphub.get_hub_instance()
        if not hub then
            return
        end
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
                            meta = {
                                is_within_variable = true,
                            },
                        },
                        parse_response = true,
                    })
                    return response.text
                end,
            }
        end
    end)
end
function M.get_mcp_tool_prompt(params)
    local action_name = params.action
    local server_name = params.server_name
    local tool_name = params.tool_name
    local uri = params.uri
    local arguments = params.arguments or {}

    local args = ""
    for k, v in pairs(arguments) do
        args = args .. k .. ":\n "
        if type(v) == "string" then
            local lines = vim.split(v, "\n")
            for _, line in ipairs(lines) do
                args = args .. line .. "\n"
            end
        else
            args = args .. vim.inspect(v) .. "\n"
        end
    end
    local msg = ""
    if action_name == "use_mcp_tool" then
        msg = string.format(
            [[Do you want to run the `%s` tool on the `%s` mcp server with arguments: 
%s]],
            tool_name,
            server_name,
            args
        )
    elseif action_name == "access_mcp_resource" then
        msg = string.format("Do you want to access the resource `%s` on the `%s` server?", uri, server_name)
    end
    return msg
end
function M.show_mcp_tool_prompt(params)
    local msg = M.get_mcp_tool_prompt(params)
    local confirm = vim.fn.confirm(msg, "&Yes\n&No", 2)
    return confirm == 1
end

function M.setup_codecompanion_tools(enabled)
    if not enabled then
        return
    end
    --INFO:Individual tools might be an overkill
end

return M
