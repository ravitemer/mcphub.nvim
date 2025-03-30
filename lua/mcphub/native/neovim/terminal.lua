local api = vim.api
local Path = require("plenary.path")
local mcphub = require("mcphub")

-- Tool to execute Lua code using nvim_exec2
mcphub.add_tool("neovim", {
    name = "execute_lua",
    description = [[Execute Lua code in Neovim using nvim_exec2 with lua heredoc.

String Formatting Guide:
1. Newlines in Code:
   - Use \n for new lines in your code
   - Example: "local x = 1\nprint(x)"

2. Newlines in Output:
   - Use \\n when you want to print newlines
   - Example: print('Line 1\\nLine 2')

3. Complex Data:
   - Use vim.print() for formatted output
   - Use vim.inspect() for complex structures
   - Both handle escaping automatically

4. String Concatenation:
   - Prefer '..' over string.format()
   - Example: print('Count: ' .. vim.api.nvim_buf_line_count(0))
]],

    inputSchema = {
        type = "object",
        properties = {
            code = {
                type = "string",
                description = "Lua code to execute",
                examples = {
                    -- Simple multiline code
                    "local bufnr = vim.api.nvim_get_current_buf()\nprint('Current buffer:', bufnr)",

                    -- Output with newlines
                    "print('Buffer Info:\\nNumber: ' .. vim.api.nvim_get_current_buf())",

                    -- Complex info with proper formatting
                    [[local bufnr = vim.api.nvim_get_current_buf()
local name = vim.api.nvim_buf_get_name(bufnr)
local ft = vim.bo[bufnr].filetype
local lines = vim.api.nvim_buf_line_count(bufnr)
print('Buffer Info:\\nBuffer Number: ' .. bufnr .. '\\nFile Name: ' .. name .. '\\nFiletype: ' .. ft .. '\\nTotal Lines: ' .. lines)]],

                    -- Using vim.print for complex data
                    [[local info = {
  buffer = vim.api.nvim_get_current_buf(),
  name = vim.api.nvim_buf_get_name(0),
  lines = vim.api.nvim_buf_line_count(0)
}
vim.print(info)]],
                },
            },
        },
        required = { "code" },
    },
    handler = function(req, res)
        local code = req.params.code
        if not code then
            return res:error("code field is required."):send()
        end

        -- Construct Lua heredoc
        local src = string.format(
            [[
lua << EOF
%s
EOF]],
            code
        )

        -- Execute with output capture
        local result = api.nvim_exec2(src, { output = true })

        if result.output then
            return res:text(result.output):send()
        else
            return res:text("Code executed successfully. (No output)"):send()
        end
    end,
})

-- Tool to execute shell commands using jobstart
mcphub.add_tool("neovim", {
    name = "execute_command",
    description = [[Execute a shell command using vim.fn.jobstart and return the result.
    
Command Execution Guide:
1. Commands run in a separate process
2. Output is captured and returned when command completes
3. Environment is inherited from Neovim
4. Working directory must be specified]],

    inputSchema = {
        type = "object",
        properties = {
            command = {
                type = "string",
                description = "Shell command to execute",
                examples = [["ls -la"]],
            },
            cwd = {
                type = "string",
                description = "Working directory for the command",
                default = ".",
            },
        },
        required = { "command", "cwd" },
    },
    handler = function(req, res)
        local command = req.params.command
        local cwd = req.params.cwd

        if not command or command == "" then
            return res:error("command field is required and cannot be empty.")
        end

        if not cwd or cwd == "" then
            return res:error("cwd field is required and cannot be empty.")
        end

        -- Use Plenary Path to handle the path
        local path = Path:new(cwd)

        -- Check if the directory exists
        if not path:exists() then
            return res:error("Directory does not exist: " .. cwd)
        end

        -- Make sure it's a directory
        if not path:is_dir() then
            return res:error("Path is not a directory: " .. cwd)
        end

        local absolute_path = path:absolute()
        local output = ""
        local stderr_output = ""

        local options = {
            cwd = absolute_path,
            on_stdout = function(_, data)
                if data then
                    for _, line in ipairs(data) do
                        if line ~= "" then
                            output = output .. line .. "\n"
                        end
                    end
                end
            end,
            on_stderr = function(_, data)
                if data then
                    for _, line in ipairs(data) do
                        if line ~= "" then
                            stderr_output = stderr_output .. line .. "\n"
                        end
                    end
                end
            end,
            on_exit = function(_, exit_code)
                local result = ""

                -- Add command information
                result = result .. "Command: " .. command .. "\n"
                result = result .. "Working Directory: " .. absolute_path .. "\n"
                result = result .. "Exit Code: " .. exit_code .. "\n"

                -- Add stdout if there's any output
                if output ~= "" then
                    result = result .. "Output:\n\n" .. output
                end

                -- Add stderr if there's any error output
                if stderr_output ~= "" then
                    result = result .. "\nError Output:\n" .. stderr_output
                end

                -- If no output was captured at all
                if output == "" and stderr_output == "" then
                    result = result .. "Command completed with no output."
                end

                res:text(result):send()
            end,
        }

        -- Start the job
        local job_id = vim.fn.jobstart(command, options)

        if job_id <= 0 then
            local error_msg
            if job_id == 0 then
                error_msg = "Invalid arguments for jobstart"
            else -- job_id == -1
                error_msg = "Command is not executable"
            end
            return res:error(error_msg)
        end
    end,
})
