local api = vim.api
local Terminal = require("toggleterm.terminal").Terminal
local mcphub = require("mcphub")

-- Get default shell with fallbacks
local function get_shell()
    local shell = vim.o.shell
    if shell == "" then
        shell = vim.fn.exepath("pwsh")
            or vim.fn.exepath("powershell")
            or vim.fn.exepath("bash")
            or vim.fn.exepath("sh")
            or vim.fn.exepath("cmd")
    end
    if shell == "" then
        error([[No shell executable found. Please ensure one of these is available:
- pwsh
- powershell
- bash
- sh
- cmd
Or set 'shell' option in Neovim]])
    end
    return shell
end

-- Clean ANSI escape codes from output
local function clean_ansi(str)
    return str
        :gsub("\27%[[0-9;]*m", "") -- Remove color codes
        :gsub("\27%[[0-9;]*[ABCDEFGJKSH]", "") -- Remove cursor movements
        :gsub("%c", " ") -- Replace other control chars with space
end

-- Helper to capture terminal output until command completes
local function capture_command_output(term, command, timeout)
    -- Track command state and output
    local command_started = false
    local result = {
        stdout = {},
        stderr = {},
        exit_code = nil,
        shell_prompt = nil,
    }

    -- Validate input
    if not term or not command then
        error("Terminal and command are required")
    end

    -- Store original handlers
    local orig = {
        stdout = term.on_stdout,
        stderr = term.on_stderr,
        exit = term.on_exit,
    }

    local function restore_handlers()
        term.on_stdout = orig.stdout
        term.on_stderr = orig.stderr
        term.on_exit = orig.exit
    end

    -- Set up output capture handlers
    term.on_stdout = function(t, job_id, data, ...)
        -- Still call original handler
        if orig.stdout then
            orig.stdout(t, job_id, data, ...)
        end

        -- Capture shell prompt if not found
        if not result.shell_prompt and data and #data > 0 then
            for _, line in ipairs(data) do
                local cleaned = clean_ansi(line)
                if cleaned:match("[@%%>$#]%s*$") then
                    result.shell_prompt = cleaned
                    break
                end
            end
        end

        -- Track command output (skip empty or invalid data)
        if not data or #data == 0 or (data[1] == "" and #data == 1) then
            return
        end

        if not command_started then
            -- Look for command echo
            for _, line in ipairs(data) do
                if line:match("^" .. vim.pesc(command)) then
                    command_started = true
                    break
                end
            end
        else
            -- Store non-empty output lines
            local lines = vim.tbl_filter(function(line)
                return line ~= ""
            end, vim.tbl_map(clean_ansi, data))
            if #lines > 0 then
                vim.list_extend(result.stdout, lines)
            end
        end
    end

    term.on_stderr = function(t, job_id, data, ...)
        if orig.stderr then
            orig.stderr(t, job_id, data, ...)
        end
        if data and #data > 0 and not (data[1] == "" and #data == 1) then
            local lines = vim.tbl_filter(function(line)
                return line ~= ""
            end, vim.tbl_map(clean_ansi, data))
            if #lines > 0 then
                vim.list_extend(result.stderr, lines)
            end
        end
    end

    term.on_exit = function(t, job_id, code, ...)
        if orig.exit then
            orig.exit(t, job_id, code, ...)
        end
        result.exit_code = code
        restore_handlers()
    end

    -- Send command and wait for completion
    vim.schedule(function()
        term:send(command)
    end)

    local ok, result_or_err = pcall(function()
        -- Wait for command completion
        local wait_success = vim.wait(
            timeout or 10000, -- timeout in ms
            function() -- condition
                return result.exit_code ~= nil
            end,
            100, -- interval between checks
            false -- don't show "waiting..." message
        )

        if not wait_success then
            error({
                type = "timeout",
                message = string.format("Command timed out after %ds", (timeout or 10000) / 1000),
            })
        end

        -- Format output
        local output = {
            prompt = result.shell_prompt,
            command = command,
            stdout = table.concat(result.stdout, "\n"),
            stderr = table.concat(result.stderr, "\n"),
            exit_code = result.exit_code,
        }

        if result.exit_code ~= 0 then
            error({
                type = "exit",
                code = result.exit_code,
                output = output,
            })
        end

        return output
    end)

    -- Always restore handlers before returning
    restore_handlers()

    if not ok then
        if type(result_or_err) == "table" then
            if result_or_err.type == "timeout" then
                error(result_or_err.message)
            elseif result_or_err.type == "exit" then
                error(
                    string.format(
                        "Command failed with exit code %d\n%s",
                        result_or_err.code,
                        vim.inspect(result_or_err.output)
                    )
                )
            end
        end
        error(result_or_err) -- Re-throw unknown errors
    end

    return result_or_err
end

-- Add terminal execution tool
mcphub.add_tool("neovim", {
    name = "run_terminal",
    description = "Run command in terminal and capture output while keeping terminal open",
    inputSchema = {
        type = "object",
        properties = {
            command = {
                type = "string",
                description = "Command to execute",
            },
            cwd = {
                type = "string",
                description = "Working directory (optional)",
            },
            env = {
                type = "object",
                description = "Environment variables (optional)",
                additionalProperties = { type = "string" },
            },
            timeout = {
                type = "number",
                description = "Command timeout in milliseconds (default: 10000)",
            },
            close_on_exit = {
                type = "boolean",
                description = "Close terminal after command (optional)",
                default = false,
            },
            shell = {
                type = "string",
                description = "Shell to use (optional)",
            },
        },
        required = { "command" },
    },
    handler = function(req, res)
        local params = req.params
        -- Initialize terminal with proper shell and environment
        local ok, shell = pcall(function()
            return params.shell or get_shell()
        end)
        if not ok then
            return res:error(shell) -- Error from get_shell()
        end
        local term = Terminal:new({
            cmd = shell,
            hidden = false,
            close_on_exit = params.close_on_exit,
            env = vim.tbl_extend("force", {
                SHELL = shell,
                TERM = "screen-256color",
            }, params.env or {}),
            on_stdout = function(_, _, data)
                -- Default prompt capture
                if data and #data > 0 then
                    local line = clean_ansi(data[1])
                    if line:match("[@%%>$#]%s*$") then
                        term.shell_prompt = line
                    end
                end
            end,
        })

        -- Start terminal and wait for shell prompt
        term:toggle()
        -- Wait for shell to initialize
        vim.wait(500, function()
            return false
        end, 100, false)

        -- Change directory if needed
        if params.cwd then
            local cd_ok, cd_result = pcall(capture_command_output, term, string.format("cd %s", params.cwd))
            if not cd_ok then
                return res:error("Failed to change directory: " .. cd_result)
            end
        end

        -- Run command with proper quoting
        local quoted_cmd = params.command:match("^%s*['\"]") and params.command or string.format("%q", params.command)
        local ok, result = pcall(capture_command_output, term, quoted_cmd, params.timeout)

        if not ok then
            return res:error(result) -- Pass actual error from pcall
        end

        -- Format response with full details
        return res:text(
            string.format(
                [[
Command: %s
Working Dir: %s
Shell: %s

%s
%s

%s
]],
                params.command,
                params.cwd or vim.fn.getcwd(),
                result.prompt or "unknown",
                string.rep("-", 40),
                result.stdout,
                result.stderr ~= "" and "\nErrors:\n" .. result.stderr or ""
            )
        ):send()
    end,
})
