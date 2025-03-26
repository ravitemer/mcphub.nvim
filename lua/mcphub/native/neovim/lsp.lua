local mcphub = require("mcphub")
local utils = require("mcphub.utils")

mcphub.add_resource("neovim", {
    name = "Current File Diagnostics",
    description = "Get diagnostics for the current file",
    uri = "neovim://diagnostics/current",
    mimeType = "plain/text",
    handler = function(req, res)
        local context = utils.parse_context(req.caller)
        local bufnr = context.bufnr
        local filepath = context.filepath
        local diagnostics = vim.diagnostic.get(bufnr)
        local text = ""
        for _, diag in ipairs(diagnostics) do
            text = text .. string.format("%s: %s [%s]\n", diag.source, diag.message, diag.severity)
        end
        return res:text(text):send()
    end,
})
