local M = {}

-- Get all diagnostics from all buffers
---@return { bufnr: number, severity: number, message: string, lnum: number, col: number }[]
function M.get_all_diagnostics()
    local all_diags = {}
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
        local diags = vim.diagnostic.get(bufnr)
        for _, diag in ipairs(diags) do
            diag.bufnr = bufnr
            table.insert(all_diags, diag)
        end
    end
    return all_diags
end

-- Get diagnostics by severity level
---@param severity string "ERROR"|"WARN"|"INFO"|"HINT"
---@return { bufnr: number, severity: number, message: string, lnum: number, col: number }[]
function M.get_diagnostics_by_severity(severity)
    local sev_num = vim.diagnostic.severity[severity:upper()]
    if not sev_num then
        error("Invalid severity: " .. severity)
    end

    local filtered = {}
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
        local diags = vim.diagnostic.get(bufnr)
        for _, diag in ipairs(diags) do
            if diag.severity == sev_num then
                diag.bufnr = bufnr
                table.insert(filtered, diag)
            end
        end
    end
    return filtered
end

return M
