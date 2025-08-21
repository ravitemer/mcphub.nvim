local types = require("mcphub.native.neovim.files.edit_file.types")

---@class BlockLocator
---@field config LocatorConfig Configuration options
---@field search_engine SearchEngine Search engine instance
local BlockLocator = {}
BlockLocator.__index = BlockLocator

-- Default locator configuration
local DEFAULT_CONFIG = {
    fuzzy_threshold = 0.8, -- Minimum similarity score for fuzzy matches
    enable_fuzzy_matching = true, -- Allow fuzzy matching when exact fails
}

-- Create new block locator instance
---@param config LocatorConfig? Optional configuration
---@return BlockLocator
function BlockLocator.new(config)
    local self = setmetatable({}, BlockLocator)
    self.config = vim.tbl_deep_extend("force", DEFAULT_CONFIG, config or {})
    local SearchEngine = require("mcphub.native.neovim.files.edit_file.search_engine")
    self.search_engine = SearchEngine.new(self.config)
    return self
end

-- Locate all blocks in file content
---@param parsed_blocks ParsedBlock[] Blocks from DiffParser
---@param file_content string Content of the target file
---@return LocatedBlock[] located_blocks Blocks with location information
function BlockLocator:locate_all_blocks(parsed_blocks, file_content)
    local file_lines = vim.split(file_content, "\n", { plain = true, trimempty = false })
    local located_blocks = {}
    for _, parsed_block in ipairs(parsed_blocks) do
        if vim.trim(parsed_block.search_content) == "" then
            parsed_block.search_content = file_content
            parsed_block.search_lines = file_lines
        end

        local location_result = self.search_engine:locate_block_in_file(parsed_block.search_lines, file_lines)

        ---@type LocatedBlock
        local located_block = {
            search_content = parsed_block.search_content,
            replace_content = parsed_block.replace_content,
            block_id = parsed_block.block_id,
            search_lines = parsed_block.search_lines,
            replace_lines = parsed_block.replace_lines,
            location_result = location_result,
        }
        table.insert(located_blocks, located_block)
    end

    return located_blocks
end

-- Get comprehensive feedback including location statistics
---@param located_blocks? LocatedBlock[] Processed blocks for statistics
---@return string? feedback Complete feedback for LLM
function BlockLocator:get_feedback(located_blocks)
    local search_logs = {}
    if located_blocks then
        for _, block in ipairs(located_blocks) do
            if not block.location_result.found then
                local found_content = block.location_result.found_content
                local best_match = ""
                local best_score = block.location_result.confidence
                if found_content then
                    best_match = string.format(
                        "\nThe following is the BEST MATCH found from Line `%s` to `%s` with `%s%%` confidence:\n",
                        block.location_result.start_line or "N/A",
                        block.location_result.end_line or "N/A",
                        best_score
                    )
                    best_match = best_match
                        .. string.format(
                            -- '<SEARCHED-CONTENT>\n%s\n</SEARCHED-CONTENT>\n<BESTMATCH confidence="%s%%" startline="%s" endline="%s">\n%s\n</BESTMATCH>',
                            '<BESTMATCH confidence="%s%%" startline="%s" endline="%s">\n%s\n</BESTMATCH>',
                            -- block.search_content,
                            best_score,
                            block.location_result.start_line or "N/A",
                            block.location_result.end_line or "N/A",
                            found_content
                        )
                else
                    best_match = ""
                end
                table.insert(
                    search_logs,
                    string.format(
                        [[
### `%s` (ERROR) 
Finding SEARCH content from `%s` failed with error: `%s`%s]],
                        block.block_id,
                        block.block_id,
                        block.location_result.error,
                        best_match
                    )
                )
            end
            local is_fuzzy = block.location_result.found
                and (
                    block.location_result.overall_match_type ~= types.OVERALL_MATCH_TYPE.exact
                    and block.location_result.overall_match_type ~= types.OVERALL_MATCH_TYPE.exact_whitespace
                )
            if is_fuzzy then
                local diff = vim.diff(block.location_result.found_content, block.search_content, {
                    result_type = "unified",
                }) --[[@as string?]]
                table.insert(
                    search_logs,
                    string.format(
                        [[
### `%s` (WARNING)
SEARCH content from `%s` is fuzzily matched and applied at LINES `%s` to `%s` with `%.2f%%` confidence:
The following is a diff for `%s` SEARCH content vs Fuzzily matched content:
```diff
%s
```]],
                        block.block_id,
                        block.block_id,
                        block.location_result.start_line,
                        block.location_result.end_line,
                        block.location_result.confidence,
                        block.block_id,
                        vim.trim(diff or "")
                    )
                )
            end
        end
    end
    if #search_logs > 0 then
        return "## ISSUES WHILE SEARCHING\n" .. table.concat(search_logs, "\n\n")
    end
end

return BlockLocator
