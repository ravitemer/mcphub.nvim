-- Search Engine for Block Location

local string_utils = require("mcphub.native.neovim.files.edit_file.string_utils")
local types = require("mcphub.native.neovim.files.edit_file.types")

---@class UsedRange
---@field start_line integer Start of used range
---@field end_line integer End of used range

---@class SearchResult
---@field score number Overall match score (0.0-1.0)
---@field start_line integer Starting line position
---@field line_details LineMatchDetail[] Per-line match details
---@field match_type OverallMatchType Type of match found

---@class SearchEngine
---@field config table Configuration options
---@field used_ranges UsedRange[] Track used line ranges to handle duplicate blocks
local SearchEngine = {}
SearchEngine.__index = SearchEngine

-- Default configuration
local DEFAULT_CONFIG = {
    fuzzy_threshold = 0.8, -- Minimum similarity score for fuzzy matches
    enable_fuzzy_matching = true, -- Allow fuzzy matching when exact fails
    early_termination_score = 1, -- Stop searching when match is this good
    max_search_iterations = 10000, -- Prevent runaway searches
}

-- Create new search engine instance
---@param config table? Optional configuration
---@return SearchEngine
function SearchEngine.new(config)
    local self = setmetatable({}, SearchEngine)
    self.config = vim.tbl_deep_extend("force", DEFAULT_CONFIG, config or {})
    self.used_ranges = {} -- Track used line ranges for duplicate handling
    return self
end

-- Reset used ranges (call this when starting a new file)
function SearchEngine:reset_used_ranges()
    self.used_ranges = {}
end

-- Main search function - top-to-bottom linear approach
---@param search_lines string[] Lines to search for
---@param file_lines string[] All file lines
---@return BlockLocationResult
function SearchEngine:locate_block_in_file(search_lines, file_lines)
    if #search_lines == 0 then
        return {
            found = true,
            start_line = 1,
            end_line = 1,
            overall_score = 1,
            overall_match_type = types.OVERALL_MATCH_TYPE.exact,
            confidence = 100,
            found_content = table.concat(file_lines, "\n"),
            found_lines = file_lines,
            line_details = {},
            search_metadata = {},
        }
    end
    -- Perform top-to-bottom linear search
    return self:_linear_search(search_lines, file_lines)
end

-- Linear top-to-bottom search that handles exact, whitespace, and fuzzy matches
---@param search_lines string[] Lines to search for
---@param file_lines string[] All file lines
---@return BlockLocationResult
function SearchEngine:_linear_search(search_lines, file_lines)
    local search_len = #search_lines
    local total_lines = #file_lines

    -- Validate bounds
    if total_lines < search_len then
        return {
            found = false,
            error = "SEARCH block lines more than file lines. If you are rewriting the file, make sure the SEARCH block is empty",
        }
    end

    ---@type SearchResult
    local best_result = {
        score = 0,
        start_line = -1,
        line_details = {},
        match_type = types.OVERALL_MATCH_TYPE.fuzzy_low, -- Default to lowest type
    }

    local iterations = 0
    local early_termination = false

    -- Search from top to bottom
    for start_pos = 1, total_lines - search_len + 1 do
        iterations = iterations + 1

        -- Check if this position is available (not used by previous blocks)
        if self:_is_position_available(start_pos, search_len) then
            local result = self:_evaluate_position(search_lines, file_lines, start_pos)

            -- For exact matches, take the first one found (top-to-bottom priority)
            if result.match_type == types.OVERALL_MATCH_TYPE.exact then
                best_result = result
                break
            end

            -- For fuzzy matches, keep track of the best one so far
            if self:_is_better_result(result, best_result) then
                best_result = result
            end
        end

        -- Prevent runaway searches
        if iterations >= self.config.max_search_iterations then
            break
        end
    end

    -- Check if we found a suitable match
    local min_score = self.config.enable_fuzzy_matching and self.config.fuzzy_threshold or 0.99
    if
        best_result.score >= min_score
        or best_result.match_type == types.OVERALL_MATCH_TYPE.exact
        or best_result.match_type == types.OVERALL_MATCH_TYPE.exact_whitespace
    then
        -- Mark this range as used
        self:_mark_range_used(best_result.start_line, best_result.start_line + search_len - 1)

        return self:_create_success_result(best_result, search_lines, file_lines)
    else
        return {
            found = false,
            error = "No suitable match found",
            overall_score = best_result.score,
            confidence = math.floor(best_result.score * 100),
            start_line = best_result.start_line,
            end_line = best_result.start_line + search_len - 1,
            found_content = table.concat(
                vim.tbl_map(function(
                    line --[[@as LineMatchDetail]]
                )
                    return line.found_line
                end, best_result.line_details),
                "\n"
            ),
        }
    end
end

-- Check if a position is available (not already used)
---@param start_line integer Starting position to check
---@param search_len integer Length of the search block
---@return boolean available True if position is available
function SearchEngine:_is_position_available(start_line, search_len)
    local end_line = start_line + search_len - 1

    -- Early exit if no used ranges
    if #self.used_ranges == 0 then
        return true
    end

    for _, used_range in ipairs(self.used_ranges) do
        -- Check for overlap: ranges overlap if NOT (a.end < b.start OR a.start > b.end)
        if not (end_line < used_range.start_line or start_line > used_range.end_line) then
            return false -- Overlaps with used range
        end
    end

    return true
end

-- Mark a range as used
---@param start_line integer Start of used range
---@param end_line integer End of used range
function SearchEngine:_mark_range_used(start_line, end_line)
    ---@type UsedRange
    local new_range = {
        start_line = start_line,
        end_line = end_line,
    }
    table.insert(self.used_ranges, new_range)
end

-- Evaluate a specific position for match quality
---@param search_lines string[] Lines to search for
---@param file_lines string[] All file lines
---@param start_pos integer Starting position to evaluate
---@return SearchResult result Match evaluation result
function SearchEngine:_evaluate_position(search_lines, file_lines, start_pos)
    local search_len = #search_lines

    -- Bounds check
    if start_pos + search_len - 1 > #file_lines then
        return {
            score = 0,
            start_line = start_pos,
            line_details = {},
            match_type = types.OVERALL_MATCH_TYPE.fuzzy_low,
        }
    end

    ---@type LineMatchDetail[]
    local line_details = {}
    local total_score = 0
    local all_exact = true
    local all_whitespace_or_better = true

    -- Analyze each line
    for i = 1, search_len do
        local search_line = search_lines[i]
        local file_line = file_lines[start_pos + i - 1]
        local absolute_line_num = start_pos + i - 1

        local match_type, line_score, differences = string_utils.compare_lines(search_line, file_line)
        total_score = total_score + line_score

        ---@type LineMatchDetail
        local line_detail = {
            line_number = absolute_line_num,
            expected_line = search_line,
            found_line = file_line,
            line_score = line_score,
            line_match_type = match_type,
            differences = differences or {},
        }
        table.insert(line_details, line_detail)

        -- Track overall match quality (early exit for performance)
        if match_type ~= types.LINE_MATCH_TYPE.exact then
            all_exact = false
        end
        if match_type ~= types.LINE_MATCH_TYPE.exact and match_type ~= types.LINE_MATCH_TYPE.exact_whitespace then
            all_whitespace_or_better = false
        end
    end

    local avg_score = total_score / search_len

    -- Determine overall match type with clear thresholds
    local overall_match_type
    if all_exact then
        overall_match_type = types.OVERALL_MATCH_TYPE.exact
    elseif all_whitespace_or_better then
        overall_match_type = types.OVERALL_MATCH_TYPE.exact_whitespace
    elseif avg_score >= 0.85 then
        overall_match_type = types.OVERALL_MATCH_TYPE.fuzzy_high
    elseif avg_score >= 0.70 then
        overall_match_type = types.OVERALL_MATCH_TYPE.fuzzy_medium
    else
        overall_match_type = types.OVERALL_MATCH_TYPE.fuzzy_low
    end

    return {
        score = avg_score,
        start_line = start_pos,
        line_details = line_details,
        match_type = overall_match_type,
    }
end

-- Check if one result is better than another
---@param new_result SearchResult New result to compare
---@param current_best SearchResult Current best result
---@return boolean is_better
function SearchEngine:_is_better_result(new_result, current_best)
    -- Define priority order for match types
    local type_priority = {
        [types.OVERALL_MATCH_TYPE.exact] = 4,
        [types.OVERALL_MATCH_TYPE.exact_whitespace] = 3,
        [types.OVERALL_MATCH_TYPE.fuzzy_high] = 2,
        [types.OVERALL_MATCH_TYPE.fuzzy_medium] = 1,
        [types.OVERALL_MATCH_TYPE.fuzzy_low] = 0,
    }

    local new_priority = type_priority[new_result.match_type] or 0
    local current_priority = type_priority[current_best.match_type] or 0

    -- First compare by match type priority
    if new_priority ~= current_priority then
        return new_priority > current_priority
    end

    -- If same priority, compare by score
    return new_result.score >= current_best.score
end

-- Create successful search result
---@param best_result table Best match found
---@param search_lines string[] Original search lines
---@param file_lines string[] All file lines
---@return BlockLocationResult
function SearchEngine:_create_success_result(best_result, search_lines, file_lines)
    local end_line = best_result.start_line + #search_lines - 1
    local found_lines = vim.list_slice(file_lines, best_result.start_line, end_line)

    return {
        found = true,
        start_line = best_result.start_line,
        end_line = end_line,
        overall_score = best_result.score,
        overall_match_type = best_result.match_type,
        confidence = math.floor(best_result.score * 100),
        found_content = table.concat(found_lines, "\n"),
        found_lines = found_lines,
        line_details = best_result.line_details,
    }
end

return SearchEngine
