local buf_utils = require("mcphub.native.neovim.utils.buffer")
local os_utils = require("mcphub.native.neovim.utils.os")

return {
    name = "Environment",
    description = function()
        return "This resource gives comprehensive information about the workspace, editor and OS. Includes directory structure, visible and loaded buffers along with the OS information."
    end,
    uri = "neovim://workspace/info",
    mimeType = "text/plain",
    handler = function(req, res)
        local editor_info = req.editor_info
        local os_info = os_utils.get_os_info()
        local dir_info = buf_utils.get_directory_info(vim.fn.getcwd())

        -- Format visible and loaded buffers
        local visible = vim.tbl_map(
            function(buf)
                return string.format("%s%s", buf.name, buf.bufnr == editor_info.last_active.bufnr and " (active)" or "")
            end,
            vim.tbl_filter(function(buf)
                return buf.is_visible
            end, editor_info.buffers)
        )

        local loaded = vim.tbl_map(
            function(buf)
                return string.format("%s%s", buf.name, buf.bufnr == editor_info.last_active.bufnr and " (active)" or "")
            end,
            vim.tbl_filter(function(buf)
                return (not buf.is_visible) and buf.is_loaded
            end, editor_info.buffers)
        )

        -- Format workspace files
        local workspace_files = vim.tbl_map(function(file)
            return string.format("%s (%s, %.2fKB)", file.name, file.type, file.size / 1024)
        end, dir_info.files)

        local text = string.format(
            [[
<environment_details>
>> System Information
OS: %s (%s)
Hostname: %s
User: %s
Shell: %s
Memory: %.2f GB total, %.2f GB free

>> Workspace
Current Directory: %s
Git Repository: %s
Files: %d

>> Workspace Files
%s

>> Neovim Visible Files
%s

>> Neovim Loaded Files
%s

>> Current Time
%s
</environment_details>
            ]],
            os_info.os_name,
            os_info.arch,
            os_info.hostname,
            os_info.env.user,
            os_info.env.shell,
            os_info.memory.total / (1024 * 1024 * 1024),
            os_info.memory.free / (1024 * 1024 * 1024),
            os_info.cwd,
            dir_info.is_git and "Yes" or "No",
            #dir_info.files,
            table.concat(workspace_files, "\n"),
            table.concat(visible, "\n"),
            table.concat(loaded, "\n"),
            os.date("%Y-%m-%d %H:%M:%S")
        )
        return res:text(text):send()
    end,
}
