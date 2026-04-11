local M = {}

local STATUS_MARKER = "__MCPHUB_STATUS__:"

local function build_command(opts)
    local cmd = { "curl", "-sS" }

    if opts.method and opts.method ~= "" then
        vim.list_extend(cmd, { "-X", opts.method })
    end

    for key, value in pairs(opts.headers or {}) do
        vim.list_extend(cmd, { "-H", string.format("%s: %s", key, value) })
    end

    if opts.body then
        vim.list_extend(cmd, { "--data-binary", opts.body })
    end

    vim.list_extend(cmd, opts.raw or {})
    vim.list_extend(cmd, opts.dump or {})
    table.insert(cmd, opts.url)
    vim.list_extend(cmd, { "-w", "\n" .. STATUS_MARKER .. "%{http_code}" })

    return cmd
end

local function parse_response(obj)
    local stdout = obj.stdout or ""
    local body, status = stdout:match("^(.*)\n" .. STATUS_MARKER .. "(%d+)$")
    if not body then
        body = stdout
        status = "0"
    end

    return {
        status = tonumber(status) or 0,
        body = body,
        exit = obj.code or 0,
        stderr = obj.stderr or "",
    }
end

---@param opts {url: string, method?: string, headers?: table, body?: string, raw?: string[], dump?: string[], callback?: function, on_error?: function}
---@return table|nil
function M.request(opts)
    local cmd = build_command(opts)

    if opts.callback then
        vim.system(cmd, { text = true }, function(obj)
            local response = parse_response(obj)
            if obj.code ~= 0 and opts.on_error then
                opts.on_error({
                    exit = obj.code,
                    stderr = obj.stderr or "",
                    message = obj.stderr or "curl request failed",
                })
                return
            end

            opts.callback(response)
        end)
        return nil
    end

    local obj = vim.system(cmd, { text = true }):wait()
    return parse_response(obj)
end

return M
