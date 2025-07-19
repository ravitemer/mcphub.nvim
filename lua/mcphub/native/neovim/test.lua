local function _ws_exact(query, cb)
    local params = { query = query }
    vim.lsp.buf_request(0, "workspace/symbol", params, function(err, result, ctx, config)
        if err then
            return vim.notify("LSP error: " .. (err.message or vim.inspect(err)), vim.log.levels.ERROR)
        end
        if not result or vim.tbl_isempty(result) then
            return vim.notify(("No symbols found for %q"):format(query), vim.log.levels.INFO)
        end
        local filtered = vim.tbl_filter(function(item)
            return item.name == query
        end, result)
        if vim.tbl_isempty(filtered) then
            return vim.notify(("No exact matches for %q"):format(query), vim.log.levels.WARN)
        end
        cb(filtered, ctx, config)
    end)
end

-- 1) Print filename + line for each exact match
local function workspace_symbol_info(query)
    _ws_exact(query, function(items)
        for _, item in ipairs(items) do
            local uri = item.location and item.location.uri or item.uri
            local range = item.location and item.location.range or item.range
            local fname = vim.uri_to_fname(uri)
            local line = range.start.line + 1
            print(string.format("%s:%d", fname, line))
        end
    end)
end

vim.api.nvim_create_user_command("WSymInfo", function(opts)
    workspace_symbol_info(opts.args)
end, { nargs = 1, desc = "Print file:line of exact SYMBOL matches" })

-- 2) Jump the current buffer to the first exact match
local function workspace_symbol_jump(query)
    _ws_exact(query, function(items)
        local item = items[1]
        local uri = item.location and item.location.uri or item.uri
        local range = item.location and item.location.range or item.range
        local buf = vim.uri_to_bufnr(uri)
        vim.fn.bufload(buf) -- ensure buffer is loaded
        vim.api.nvim_set_current_buf(buf)
        vim.api.nvim_win_set_cursor(0, { range.start.line + 1, range.start.character })
    end)
end

vim.api.nvim_create_user_command("WSymGo", function(opts)
    workspace_symbol_jump(opts.args)
end, { nargs = 1, desc = "Jump to first exact SYMBOL definition" })

local function workspace_symbol_hover(query)
    local promise = {}
    local fulfill = function() end -- Default no-op function
    local reject = function() end -- Default no-op function
    promise.resolve, promise.reject =
        function(value)
            fulfill(value)
        end, function(err)
            reject(err)
        end

    _ws_exact(query, function(items)
        local item = items[1]
        local uri = item.location and item.location.uri or item.uri
        local range = item.location and item.location.range or item.range
        local bufnr = vim.uri_to_bufnr(uri)
        vim.fn.bufload(bufnr)

        local params = {
            textDocument = { uri = uri },
            position = range.start,
        }
        local clients = vim.lsp.get_active_clients({ bufnr = bufnr })
        if #clients == 0 then
            return promise.reject("No LSP client on buffer for " .. query)
        end

        clients[1]:request("textDocument/hover", params, function(err, result)
            if err then
                return promise.reject("Hover error: " .. (err.message or err))
            end
            if not (result and result.contents) then
                return promise.reject("No hover info for " .. query)
            end

            -- convert to markdown lines
            local lines = vim.lsp.util.convert_input_to_markdown_lines(result.contents)
            vim.lsp.util.trim_empty_lines(lines)

            -- extract first code block only
            local snippet = {}
            local in_block = false
            for _, l in ipairs(lines) do
                if l:match("^```") then
                    if not in_block then
                        in_block = true -- start of first fence
                    else
                        break -- end of first fence
                    end
                elseif in_block then
                    snippet[#snippet + 1] = l
                end
            end

            if #snippet == 0 then
                -- fallback: return all lines
                promise.resolve(lines)
            else
                promise.resolve(snippet)
            end
        end, bufnr)
    end)

    -- Return a function that takes a callback
    return function(callback)
        fulfill = callback or function() end
        reject = function(err)
            vim.notify(err, vim.log.levels.ERROR)
            if callback then
                callback(nil, err)
            end
        end
    end
end

-- re-create the command
vim.api.nvim_create_user_command("WSymHover", function(opts)
    local result_handler = workspace_symbol_hover(opts.args)
    result_handler(function(lines, err)
        if err then
            print("Error:", err)
            return
        end
        -- Do something with the lines
        print(table.concat(lines, "\n"))
    end)
end, {
    nargs = 1,
    desc = "Fetch exact SYMBOL definition via hover (first code block only)",
})

local mcphub = require("mcphub")
mcphub.add_tool("neovim", {
    name = "get_definition",
    description = "Get a definition of a symbol",

    inputSchema = {
        type = "object",
        properties = {
            symbol_name = {
                type = "string",
                description = "Symbol name to get definition for",
                examples = {
                    "my_function",
                    "MyClass",
                    "my_variable",
                },
            },
        },
        required = { "symbol_name" },
    },
    handler = function(req, res)
        local symbol_name = req.params.symbol_name
        if not symbol_name or symbol_name == "" then
            res:error("Symbol name is required"):send()
            return
        end

        print("Looking up symbol: " .. symbol_name)

        -- Track response status
        local response_sent = false
        local function send_response(fn)
            if not response_sent then
                response_sent = true
                pcall(fn)
            end
        end

        -- Set a simple timeout using a flag
        local timed_out = false
        vim.defer_fn(function()
            if not response_sent then
                timed_out = true
                send_response(function()
                    print("Timeout for: " .. symbol_name)
                    res:error("Operation timed out"):send()
                end)
            end
        end, 10000)

        -- Find all buffers with LSP support
        local buffers = vim.api.nvim_list_bufs()
        local lsp_buffers = {}

        for _, bufnr in ipairs(buffers) do
            if vim.api.nvim_buf_is_loaded(bufnr) then
                local clients = vim.lsp.get_active_clients({ bufnr = bufnr })
                if clients and #clients > 0 then
                    table.insert(lsp_buffers, {
                        bufnr = bufnr,
                        client = clients[1],
                        filename = vim.api.nvim_buf_get_name(bufnr),
                    })
                end
            end
        end

        if #lsp_buffers == 0 then
            send_response(function()
                res:error("No LSP clients available in any buffer. Open a file with LSP support."):send()
            end)
            return
        end

        print("Found " .. #lsp_buffers .. " buffers with LSP support")

        -- Try each buffer until we get a successful result
        local attempts = 0
        local max_attempts = #lsp_buffers

        -- Function to try the next buffer
        local function try_next_buffer(index)
            if timed_out or index > max_attempts then
                if not response_sent then
                    send_response(function()
                        res:error("Failed after trying " .. attempts .. " LSP buffers"):send()
                    end)
                end
                return
            end

            attempts = attempts + 1
            local buffer_info = lsp_buffers[index]
            print("Trying buffer " .. buffer_info.bufnr .. " (" .. buffer_info.filename .. ")")

            -- Use workspace/symbol request with the LSP client directly
            local params = { query = symbol_name }

            -- Add error handling for the request
            local request_success, request_error = pcall(function()
                buffer_info.client.request("workspace/symbol", params, function(err, result, ctx)
                    if timed_out or response_sent then
                        return
                    end

                    if err then
                        print("LSP error on buffer " .. buffer_info.bufnr .. ": " .. vim.inspect(err))
                        -- Try next buffer instead of failing
                        try_next_buffer(index + 1)
                        return
                    end

                    if not result or vim.tbl_isempty(result) then
                        print("No symbols found on buffer " .. buffer_info.bufnr)
                        -- Try next buffer instead of failing
                        try_next_buffer(index + 1)
                        return
                    end

                    -- Find exact match
                    local matches = vim.tbl_filter(function(item)
                        return item.name == symbol_name
                    end, result)

                    if vim.tbl_isempty(matches) then
                        print("No exact matches on buffer " .. buffer_info.bufnr)
                        -- Try next buffer
                        try_next_buffer(index + 1)
                        return
                    end

                    local item = matches[1]
                    local uri = item.location and item.location.uri or item.uri
                    local range = item.location and item.location.range or item.range

                    if not uri or not range then
                        print("Invalid symbol information on buffer " .. buffer_info.bufnr)
                        try_next_buffer(index + 1)
                        return
                    end

                    -- Found a match!
                    local symbol_bufnr = vim.uri_to_bufnr(uri)

                    -- Load buffer safely
                    local load_success, load_error = pcall(vim.fn.bufload, symbol_bufnr)
                    if not load_success then
                        print("Failed to load buffer: " .. tostring(load_error))
                        try_next_buffer(index + 1)
                        return
                    end

                    -- Get hover info with error handling
                    local hover_params = {
                        textDocument = { uri = uri },
                        position = range.start,
                    }

                    local hover_success, hover_error = pcall(function()
                        buffer_info.client.request("textDocument/hover", hover_params, function(hover_err, hover_result)
                            if timed_out or response_sent then
                                return
                            end

                            if hover_err then
                                print("Hover error: " .. vim.inspect(hover_err))
                                -- Try reading the file directly as fallback
                                local fname = vim.uri_to_fname(uri)
                                local file_lines = {}

                                pcall(function()
                                    file_lines = vim.fn.readfile(fname)
                                end)

                                send_response(function()
                                    if #file_lines > 0 then
                                        -- Show some context around the definition
                                        local start_line = math.max(1, range.start.line - 3)
                                        local end_line = math.min(#file_lines, range.start.line + 20)
                                        local context_lines = {}

                                        for i = start_line, end_line do
                                            table.insert(context_lines, file_lines[i])
                                        end

                                        res:text(table.concat(context_lines, "\n")):send()
                                    else
                                        local simple_info = "Symbol found at " .. fname .. ":" .. (range.start.line + 1)
                                        res:text(simple_info):send()
                                    end
                                end)
                                return
                            end

                            if not hover_result or not hover_result.contents then
                                -- Try fallback to file content
                                local fname = vim.uri_to_fname(uri)
                                send_response(function()
                                    res
                                        :text(
                                            "Symbol found at "
                                                .. fname
                                                .. ":"
                                                .. (range.start.line + 1)
                                                .. " (no documentation available)"
                                        )
                                        :send()
                                end)
                                return
                            end

                            -- Process hover result
                            local lines = vim.lsp.util.convert_input_to_markdown_lines(hover_result.contents)
                            vim.lsp.util.trim_empty_lines(lines)

                            -- Extract code block
                            local snippet = {}
                            -- local in_block = false
                            -- for _, l in ipairs(lines) do
                            --     if l:match("^```") then
                            --         if not in_block then
                            --             in_block = true
                            --         else
                            --             break
                            --         end
                            --     elseif in_block then
                            --         snippet[#snippet + 1] = l
                            --     end
                            -- end

                            send_response(function()
                                if #snippet == 0 then
                                    res:text(table.concat(lines, "\n")):send()
                                else
                                    res:text(table.concat(snippet, "\n")):send()
                                end
                            end)
                        end)
                    end)

                    if not hover_success then
                        print("Failed to send hover request: " .. tostring(hover_error))
                        -- Try next buffer
                        try_next_buffer(index + 1)
                    end
                end)
            end)

            if not request_success then
                print("Failed to send workspace/symbol request: " .. tostring(request_error))
                -- Try next buffer
                try_next_buffer(index + 1)
            end
        end

        -- start the process with the first buffer
        try_next_buffer(1)
    end,
})
