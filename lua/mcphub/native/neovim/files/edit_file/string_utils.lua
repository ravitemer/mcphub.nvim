-- String utilities for normalization and comparison
-- Used by the enhanced search engine for fuzzy matching

local M = {}

-- Character mappings for comprehensive normalization
local NORMALIZATION_MAPS = {
    -- Smart quotes to regular quotes
    SMART_QUOTES = {
        ["\u{201C}"] = '"', -- Left double quote (U+201C)
        ["\u{201D}"] = '"', -- Right double quote (U+201D)
        ["\u{2018}"] = "'", -- Left single quote (U+2018)
        ["\u{2019}"] = "'", -- Right single quote (U+2019)
        ['"'] = '"', -- Alternative left double quote
        ['"'] = '"', -- Alternative right double quote
        ["'"] = "'", -- Alternative left single quote
        ["'"] = "'", -- Alternative right single quote
    },

    -- Typographic characters
    TYPOGRAPHIC = {
        ["\u{2026}"] = "...", -- Ellipsis
        ["\u{2014}"] = "-", -- Em dash
        ["\u{2013}"] = "-", -- En dash
        ["\u{00A0}"] = " ", -- Non-breaking space
        ["…"] = "...", -- Ellipsis (alternative)
        ["—"] = "-", -- Em dash (alternative)
        ["–"] = "-", -- En dash (alternative)
    },

    -- HTML entities (common in copied code)
    HTML_ENTITIES = {
        ["&lt;"] = "<",
        ["&gt;"] = ">",
        ["&quot;"] = '"',
        ["&#39;"] = "'",
        ["&apos;"] = "'",
        ["&amp;"] = "&",
    },
}

-- Normalization options
---@class NormalizeOptions
---@field smart_quotes boolean Replace smart quotes with straight quotes
---@field typographic_chars boolean Replace typographic characters
---@field html_entities boolean Unescape HTML entities
---@field extra_whitespace boolean Collapse multiple whitespace to single space
---@field trim boolean Trim whitespace from start and end
---@field normalize_case boolean Convert to lowercase for comparison

local DEFAULT_NORMALIZE_OPTIONS = {
    smart_quotes = true,
    typographic_chars = true,
    html_entities = true,
    extra_whitespace = true,
    trim = true,
    normalize_case = false, -- Keep original case by default
}

-- Enhanced string normalization with comprehensive character mapping
---@param str string Input string
---@param options NormalizeOptions? Normalization options
---@return string normalized Normalized string
function M.normalize_string(str, options)
    if not str then
        return ""
    end

    options = vim.tbl_deep_extend("force", DEFAULT_NORMALIZE_OPTIONS, options or {})
    local normalized = str

    -- Replace smart quotes
    if options.smart_quotes then
        for smart_char, regular_char in pairs(NORMALIZATION_MAPS.SMART_QUOTES) do
            normalized = normalized:gsub(vim.pesc(smart_char), regular_char)
        end
    end

    -- Replace typographic characters
    if options.typographic_chars then
        for typo_char, regular_char in pairs(NORMALIZATION_MAPS.TYPOGRAPHIC) do
            normalized = normalized:gsub(vim.pesc(typo_char), regular_char)
        end
    end

    -- Unescape HTML entities
    if options.html_entities then
        for entity, char in pairs(NORMALIZATION_MAPS.HTML_ENTITIES) do
            normalized = normalized:gsub(vim.pesc(entity), char)
        end
    end

    -- Normalize whitespace
    if options.extra_whitespace then
        normalized = normalized:gsub("%s+", " ")
    end

    -- Normalize case
    if options.normalize_case then
        normalized = normalized:lower()
    end

    -- Trim whitespace
    if options.trim then
        normalized = normalized:gsub("^%s+", ""):gsub("%s+$", "")
    end

    return normalized
end

-- Quick normalization for common code comparison scenarios
---@param str string Input string
---@return string normalized Normalized string optimized for code comparison
function M.normalize_for_code(str)
    return M.normalize_string(str, {
        smart_quotes = true,
        typographic_chars = true,
        html_entities = true,
        extra_whitespace = true,
        trim = true,
        normalize_case = false, -- Preserve case for code
    })
end

-- Aggressive normalization for fuzzy matching
---@param str string Input string
---@return string normalized Heavily normalized string for fuzzy matching
function M.normalize_aggressive(str)
    return M.normalize_string(str, {
        smart_quotes = true,
        typographic_chars = true,
        html_entities = true,
        extra_whitespace = true,
        trim = true,
        normalize_case = true, -- Ignore case for fuzzy matching
    })
end

-- Normalize punctuation for flexible matching
---@param line string Input line
---@return string normalized Line with normalized punctuation
function M.normalize_punctuation(line)
    line = line
        -- Remove trailing commas and semicolons
        :gsub(",%s*$", "")
        :gsub(";%s*$", "")
        -- Normalize comma and semicolon spacing
        :gsub("%s*,%s*", ", ")
        :gsub("%s*;%s*", "; ")
        -- Normalize parentheses spacing
        :gsub("%s*%(%s*", "(")
        :gsub("%s*%)%s*", ")")
        -- Normalize bracket spacing
        :gsub("%s*%[%s*", "[")
        :gsub("%s*%]%s*", "]")
        -- Normalize brace spacing
        :gsub("%s*{%s*", "{")
        :gsub("%s*}%s*", "}")
    return line
end

-- Levenshtein distance implementation for accurate string similarity
---@param str1 string First string
---@param str2 string Second string
---@return integer distance Edit distance between strings
function M.levenshtein_distance(str1, str2)
    local len1, len2 = #str1, #str2

    -- Handle edge cases
    if len1 == 0 then
        return len2
    end
    if len2 == 0 then
        return len1
    end
    if str1 == str2 then
        return 0
    end

    -- Initialize matrix
    local matrix = {}
    for i = 0, len1 do
        matrix[i] = { [0] = i } -- Cost to delete i characters
    end
    for j = 0, len2 do
        matrix[0][j] = j -- Cost to insert j characters
    end

    -- Fill matrix using dynamic programming
    for i = 1, len1 do
        for j = 1, len2 do
            local cost = str1:sub(i, i) == str2:sub(j, j) and 0 or 1

            matrix[i][j] = math.min(
                matrix[i - 1][j] + 1, -- DELETE: remove char from str1
                matrix[i][j - 1] + 1, -- INSERT: add char to str1
                matrix[i - 1][j - 1] + cost -- SUBSTITUTE: replace char (or keep if same)
            )
        end
    end

    return matrix[len1][len2]
end

-- Calculate similarity score between two strings (0.0 to 1.0)
---@param str1 string First string
---@param str2 string Second string
---@return number similarity Similarity score (1.0 = identical, 0.0 = completely different)
function M.calculate_similarity(str1, str2)
    if str1 == str2 then
        return 1.0
    end

    local distance = M.levenshtein_distance(str1, str2)
    local max_length = math.max(#str1, #str2)

    return max_length > 0 and (1 - distance / max_length) or 0
end

local types = require("mcphub.native.neovim.files.edit_file.types")

-- Advanced line comparison with multiple normalization levels
---@param line1 string First line
---@param line2 string Second line
---@return LineMatchType match_type Type of match found
---@return number score Similarity score
---@return DifferenceType[]? differences List of difference types found
function M.compare_lines(line1, line2)
    -- Level 1: Exact match
    if line1 == line2 then
        return types.LINE_MATCH_TYPE.exact, 1.0, {}
    end

    -- Level 2: Whitespace-only normalization (common case)
    local ws_norm1 = vim.trim(line1):gsub("%s+", " ")
    local ws_norm2 = vim.trim(line2):gsub("%s+", " ")
    if ws_norm1 == ws_norm2 then
        return types.LINE_MATCH_TYPE.exact_whitespace, 0.99, { types.DIFFERENCE_TYPE.whitespace }
    end

    -- Level 3: Code normalization (smart quotes, HTML entities, whitespace)
    local code_norm1 = M.normalize_for_code(line1)
    local code_norm2 = M.normalize_for_code(line2)
    if code_norm1 == code_norm2 then
        local differences = M._detect_differences(line1, line2)
        return types.LINE_MATCH_TYPE.normalized, 0.98, differences
    end

    -- Level 4: Punctuation flexible match (common formatter changes)
    local punct1 = M.normalize_punctuation(code_norm1)
    local punct2 = M.normalize_punctuation(code_norm2)
    if punct1 == punct2 then
        local differences = M._detect_differences(line1, line2)
        table.insert(differences, types.DIFFERENCE_TYPE.punctuation)
        return types.LINE_MATCH_TYPE.punctuation, 0.95, differences
    end

    -- Level 5: Case-insensitive comparison (aggressive normalization)
    local aggr1 = M.normalize_aggressive(line1)
    local aggr2 = M.normalize_aggressive(line2)
    if aggr1 == aggr2 then
        local differences = M._detect_differences(line1, line2)
        table.insert(differences, types.DIFFERENCE_TYPE.case)
        return types.LINE_MATCH_TYPE.case_insensitive, 0.90, differences
    end

    -- Level 6: Fuzzy similarity using Levenshtein on normalized strings
    local similarity = M.calculate_similarity(aggr1, aggr2)
    local differences = M._detect_differences(line1, line2)

    if similarity >= 0.85 then
        return types.LINE_MATCH_TYPE.fuzzy_high, similarity, differences
    elseif similarity >= 0.70 then
        return types.LINE_MATCH_TYPE.fuzzy_medium, similarity, differences
    elseif similarity >= 0.50 then
        return types.LINE_MATCH_TYPE.fuzzy_low, similarity, differences
    else
        return types.LINE_MATCH_TYPE.no_match, similarity, differences
    end
end

-- Detect what types of differences exist between two lines
---@param line1 string First line
---@param line2 string Second line
---@return DifferenceType[] differences List of difference types
function M._detect_differences(line1, line2)
    local differences = {}

    -- Check for quote style differences
    if line1:gsub("'", '"') == line2:gsub("'", '"') or line1:gsub('"', "'") == line2:gsub('"', "'") then
        table.insert(differences, types.DIFFERENCE_TYPE.quote_style)
    end

    -- Check for whitespace differences
    if vim.trim(line1):gsub("%s+", " ") == vim.trim(line2):gsub("%s+", " ") then
        table.insert(differences, types.DIFFERENCE_TYPE.whitespace)
    end

    -- Check for case differences
    if line1:lower() == line2:lower() then
        table.insert(differences, types.DIFFERENCE_TYPE.case)
    end

    -- Check for HTML entity differences
    local html_norm1 =
        M.normalize_string(line1, { html_entities = true, smart_quotes = false, typographic_chars = false })
    local html_norm2 =
        M.normalize_string(line2, { html_entities = true, smart_quotes = false, typographic_chars = false })
    if html_norm1 == html_norm2 and line1 ~= line2 then
        table.insert(differences, types.DIFFERENCE_TYPE.html_entities)
    end

    return differences
end

return M
