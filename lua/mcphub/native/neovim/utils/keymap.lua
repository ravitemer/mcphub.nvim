local M = {}

--- Safely get keymap info for a specific key in a buffer
---@param mode string The mode (e.g., 'n', 'i', 'v')
---@param lhs string The left-hand side of the mapping
---@param buffer integer Buffer number
---@return table|nil Original keymap info or nil if not found
function M.get_keymap_info(mode, lhs, buffer)
    local maps = vim.api.nvim_buf_get_keymap(buffer, mode)
    for _, map in ipairs(maps) do
        if map.lhs == lhs then
            vim.notify("Found keymap: " .. lhs .. " in buffer " .. buffer, vim.log.levels.INFO)
            return map
        end
    end
    return nil
end

--- Restore a previously stored keymap
---@param mode string The mode (e.g., 'n', 'i', 'v')
---@param lhs string The left-hand side of the mapping
---@param buffer integer Buffer number
---@param original_map table|nil Original keymap info from get_keymap_info
function M.restore_keymap(mode, lhs, buffer, original_map)
    pcall(vim.keymap.del, mode, lhs, { buffer = buffer })
    if original_map then
        -- If there was an original mapping, restore it
        local opts = {
            buffer = buffer,
            desc = original_map.desc,
            nowait = original_map.nowait == 1,
            silent = original_map.silent == 1,
            expr = original_map.expr == 1,
        }

        if original_map.callback then
            vim.keymap.set(mode, lhs, original_map.callback, opts)
        elseif original_map.rhs then
            vim.keymap.set(mode, lhs, original_map.rhs, opts)
        end
    end
end

--- Store original keymaps for multiple keys
---@param mode string The mode (e.g., 'n', 'i', 'v')
---@param keys table<string, any> Table of key mappings where keys are lhs
---@param buffer integer Buffer number
---@return table<string, table|nil> Table of original keymap info
function M.store_original_keymaps(mode, keys, buffer)
    local original_maps = {}
    for lhs, _ in pairs(keys) do
        original_maps[lhs] = M.get_keymap_info(mode, lhs, buffer)
    end
    return original_maps
end

--- Restore multiple keymaps and clean up temporary ones
---@param mode string The mode (e.g., 'n', 'i', 'v')
---@param keys table<string, any> Table of key mappings where keys are lhs
---@param buffer integer Buffer number
---@param original_maps table<string, table|nil> Original keymap info from store_original_keymaps
function M.restore_keymaps(mode, keys, buffer, original_maps)
    for _, lhs in pairs(keys) do
        -- Restore original keymaps if they existed
        M.restore_keymap(mode, lhs, buffer, original_maps[lhs])
    end
end

return M
