local api = vim.api
local mcphub = require("mcphub")
-- local lazy = require("toggleterm.lazy")
-- local ui = lazy.require("toggleterm.ui")
-- local Terminal = require("toggleterm.terminal").Terminal

-- -- Tool to execute shell commands in terminal
-- mcphub.add_tool("neovim", {
--     name = "execute_in_terminal",
--     description = "Execute a command in a floating terminal and return the output",
--     inputSchema = {
--         type = "object",
--         properties = {
--             command = {
--                 type = "string",
--                 description = "Command to execute",
--                 examples = { "ls -la", "echo 'Hello World'" },
--             },
--         },
--         required = { "command" },
--     },
--     handler = function(req, res)
--         local command = req.params.command
--         local output = {}

--         -- Create terminal without initial command to show shell prompt
--         local term = Terminal:new({
--             direction = "float",
--             float_opts = {
--                 border = "single",
--                 width = 80,
--                 height = 20,
--             },
--             on_stdout = function(_, job, data)
--                 if data then
--                     for _, line in ipairs(data) do
--                         if line ~= "" then
--                             table.insert(output, line)
--                         end
--                     end
--                 end
--             end,
--             on_stderr = function(_, job, data)
--                 if data then
--                     for _, line in ipairs(data) do
--                         if line ~= "" then
--                             table.insert(output, "ERROR: " .. line)
--                         end
--                     end
--                 end
--             end,
--             close_on_exit = false, -- Keep terminal open
--         })

--         -- Open terminal first to show shell prompt
--         term:open()

--         -- Give a small delay for shell to initialize
--         vim.defer_fn(function()
--             -- Send command to terminal
--             term:send(command)
--         end, 100)

--         -- Wait for command to complete
--         vim.wait(5000, function()
--             return not term:is_running()
--         end, 100)

--         -- Convert output table to string
--         local result = table.concat(output, "\n")
--         if result == "" then
--             result = "Command executed. (No output)"
--         end

--         return res:text(result):send()
--     end,
-- })

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
