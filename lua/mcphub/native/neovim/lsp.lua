local lsp_utils = require("mcphub.native.neovim.utils.lsp")
local mcphub = require("mcphub")

mcphub.add_resource("neovim", {
    name = "Diagnostics: Current File",
    description = "Get diagnostics for the current file",
    uri = "neovim://diagnostics/current",
    mimeType = "text/plain",
    handler = function(req, res)
        -- local context = utils.parse_context(req.caller)
        local buf_info = req.editor_info.last_active
        if not buf_info then
            return res:error("No active buffer found")
        end
        local bufnr = buf_info.bufnr
        local filepath = buf_info.filename
        local diagnostics = vim.diagnostic.get(bufnr)
        local text = string.format("Diagnostics for: %s\n%s\n", filepath, string.rep("-", 40))
        for _, diag in ipairs(diagnostics) do
            local severity = vim.diagnostic.severity[diag.severity] or "UNKNOWN"
            local line_str = string.format("Line %d, Col %d", diag.lnum + 1, diag.col + 1)
            local source = diag.source and string.format("[%s]", diag.source) or ""
            local code = diag.code and string.format(" (%s)", diag.code) or ""

            -- Get range information if available
            local range_info = ""
            if diag.end_lnum and diag.end_col then
                range_info = string.format(" to Line %d, Col %d", diag.end_lnum + 1, diag.end_col + 1)
            end

            text = text
                .. string.format(
                    "\n%s: %s\n  Location: %s%s\n  Message: %s%s\n",
                    severity,
                    source,
                    line_str,
                    range_info,
                    diag.message,
                    code
                )

            text = text .. string.rep("-", 40) .. "\n"
        end
        return res:text(text ~= "" and text or "No diagnostics found"):send()
    end,
})

mcphub.add_resource("neovim", {
    name = "Diagnostics: Workspace",
    description = "Get diagnostics for all open buffers",
    uri = "neovim://diagnostics/workspace",
    mimeType = "text/plain",
    handler = function(req, res)
        local diagnostics = lsp_utils.get_all_diagnostics()
        local text = "Workspace Diagnostics\n" .. string.rep("=", 40) .. "\n\n"

        -- Group diagnostics by buffer
        local by_buffer = {}
        for _, diag in ipairs(diagnostics) do
            by_buffer[diag.bufnr] = by_buffer[diag.bufnr] or {}
            table.insert(by_buffer[diag.bufnr], diag)
        end

        -- Format diagnostics for each buffer
        for bufnr, diags in pairs(by_buffer) do
            local filename = vim.api.nvim_buf_get_name(bufnr)
            text = text .. string.format("File: %s\n%s\n", filename, string.rep("-", 40))

            for _, diag in ipairs(diags) do
                local severity = vim.diagnostic.severity[diag.severity] or "UNKNOWN"
                local line_str = string.format("Line %d, Col %d", diag.lnum + 1, diag.col + 1)
                local source = diag.source and string.format("[%s]", diag.source) or ""
                local code = diag.code and string.format(" (%s)", diag.code) or ""

                -- Get range information if available
                local range_info = ""
                if diag.end_lnum and diag.end_col then
                    range_info = string.format(" to Line %d, Col %d", diag.end_lnum + 1, diag.end_col + 1)
                end

                text = text
                    .. string.format(
                        "\n%s: %s\n  Location: %s%s\n  Message: %s%s\n",
                        severity,
                        source,
                        line_str,
                        range_info,
                        diag.message,
                        code
                    )
            end
            text = text .. string.rep("-", 40) .. "\n\n"
        end

        return res:text(text ~= "" and text or "No diagnostics found"):send()
    end,
})

mcphub.add_tool("neovim", {
    name = "get_workspace_symbols",
    description = "Get all symbols from the current workspace grouped by file",
    inputSchema = {
        type = "object",
        properties = {
            query = {
                type = "string",
                description = "Optional search query to filter symbols",
                examples = { "", "MyClass", "render" },
            },
        },
    },
    handler = function(req, res)
        -- Get current workspace directory
        local cwd = vim.fn.getcwd()

        -- Get all buffers in workspace
        local buffers = {}
        for _, buf in ipairs(vim.api.nvim_list_bufs()) do
            local name = vim.api.nvim_buf_get_name(buf)
            if name and name ~= "" then
                local abs_path = vim.fn.fnamemodify(name, ":p")
                if vim.startswith(abs_path, cwd) then
                    table.insert(buffers, {
                        bufnr = buf,
                        name = name,
                    })
                end
            end
        end

        -- Get active LSP clients
        local clients = vim.lsp.get_active_clients()
        if #clients == 0 then
            return res:error("No active LSP clients found")
        end

        -- Find a client that supports document symbols
        local client
        for _, c in ipairs(clients) do
            if c.server_capabilities.documentSymbolProvider then
                client = c
                break
            end
        end

        if not client then
            return res:error("No LSP client with document symbol support found")
        end

        -- Collect symbols from all workspace files
        local files = {}
        local file_symbols = {}

        for _, buf in ipairs(buffers) do
            local params = { textDocument = vim.lsp.util.make_text_document_params(buf.bufnr) }
            local results = client.request_sync("textDocument/documentSymbol", params, 1000, buf.bufnr)

            if results and not results.err then
                local symbols = vim.lsp.util.symbols_to_items(results.result or {}, buf.bufnr) or {}

                if #symbols > 0 then
                    local rel_path = vim.fn.fnamemodify(buf.name, ":.")
                    file_symbols[rel_path] = symbols
                    table.insert(files, rel_path)
                end
            end
        end

        if #files == 0 then
            return res:error("No symbols found in workspace files")
        end

        -- Format the output
        local query = req.params.query
        if query then
            -- Filter symbols if query is provided
            for file, symbols in pairs(file_symbols) do
                local filtered = {}
                for _, sym in ipairs(symbols) do
                    if vim.fn.stridx(string.lower(sym.text), string.lower(query)) ~= -1 then
                        table.insert(filtered, sym)
                    end
                end
                if #filtered > 0 then
                    file_symbols[file] = filtered
                else
                    file_symbols[file] = nil
                    for i, f in ipairs(files) do
                        if f == file then
                            table.remove(files, i)
                            break
                        end
                    end
                end
            end
        end

        local formatted = {}
        table.insert(
            formatted,
            string.format("Workspace Symbols%s (in %s):", query and string.format(" matching '%s'", query) or "", cwd)
        )
        table.insert(formatted, string.rep("=", 40))
        table.insert(formatted, "")

        -- Output symbols by file
        for _, file in ipairs(files) do
            table.insert(formatted, string.format("File: %s", file))
            table.insert(formatted, string.rep("-", 40))

            local symbols = file_symbols[file]
            table.sort(symbols, function(a, b)
                return a.lnum < b.lnum
            end)

            for _, sym in ipairs(symbols) do
                table.insert(formatted, string.format("  %s (%s) - line %d", sym.text, sym.kind, sym.lnum))
            end
            table.insert(formatted, "")
        end

        -- Use MCP's file tools to update the file
        return res:text(table.concat(formatted, "\n")):send()
    end,
})
