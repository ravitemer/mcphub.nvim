local lsp_utils = require("mcphub.native.neovim.utils.lsp")
local mcphub = require("mcphub")

mcphub.add_resource("neovim", {
    name = "Diagnostics: Buffer",
    description = "Get diagnostics for the current file",
    uri = "neovim://diagnostics/buffer",
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
