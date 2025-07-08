local State = require("mcphub.state")
-- Core write file logic
local function handle_write_file(req, res)
    if not req.params.path then
        return res:error("Missing required parameter: path")
    end
    if not req.params.content then
        return res:error("Missing required parameter: content")
    end
    local path = req.params.path
    local content = req.params.content or ""
    if req.caller and req.caller.type == "hubui" then
        req.caller.hubui:cleanup()
    end

    local EditSession = require("mcphub.native.neovim.files.edit_file.edit_session")
    local session = EditSession.new(path, "", State.config.builtin_tools.edit_file)
    session:start({
        replace_file_content = content,
        interactive = req.caller.auto_approve ~= true,
        on_success = function(summary)
            res:text(summary):send()
        end,
        on_error = function(error_report)
            res:error(error_report)
        end,
    })
end

---@type MCPTool
return {
    name = "write_file",
    description = "Write content to a file",
    inputSchema = {
        type = "object",
        properties = {
            path = {
                type = "string",
                description = "Path to the file to write",
            },
            content = {
                type = "string",
                description = "Content to write to the file",
            },
        },
        required = { "path", "content" },
    },
    needs_confirmation_window = false, -- will show interactive diff, avoid double confirmations
    handler = handle_write_file,
}
