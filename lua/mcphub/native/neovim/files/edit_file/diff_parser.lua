local issue_tracker = require("mcphub.native.neovim.files.edit_file.issue_tracker")

---@class DiffParser
---@field config ParserConfig Configuration options
---@field tracker IssueTracker Issue tracking instance
local DiffParser = {}
DiffParser.__index = DiffParser

-- Default parser configuration
local DEFAULT_CONFIG = {
    track_issues = true, -- Track parsing issues for LLM feedback
    extract_inline_content = true, -- Handle content on marker lines
}

-- Create new diff parser instance
---@param config ParserConfig? Optional configuration
---@return DiffParser
function DiffParser.new(config)
    local self = setmetatable({}, DiffParser)
    self.config = vim.tbl_deep_extend("force", DEFAULT_CONFIG, config or {})
    self.tracker = issue_tracker.new()
    return self
end

-- Parse diff string into structured blocks
---@param diff_content string Raw diff content from LLM
---@return ParsedBlock[]? blocks Parsed blocks (nil on error)
---@return string? error_message Error message if parsing failed
function DiffParser:parse(diff_content)
    if not diff_content or diff_content == "" then
        return nil, "Empty diff content"
    end

    -- Clear previous issues
    self.tracker:clear()

    -- Normalize and fix malformed content
    local normalized_diff = self:_normalize_content(diff_content)
    local fixed_diff = self:_fix_malformed_diff(normalized_diff)

    -- Parse the diff into blocks
    local blocks, error = self:_parse_blocks(fixed_diff)
    if error then
        return nil, error
    end

    return blocks, nil
end

-- Check if any issues were found
---@return boolean has_issues
function DiffParser:has_issues()
    return self.tracker:has_issues()
end

-- Clear tracked issues
function DiffParser:clear_issues()
    self.tracker:clear()
end

-- Normalize line endings and basic cleanup
---@param diff_content string Raw diff content
---@return string normalized_content
function DiffParser:_normalize_content(diff_content)
    -- Normalize line endings
    local text = diff_content:gsub("\r\n", "\n"):gsub("\r", "\n")
    return text
end

-- Fix common malformed diff patterns from LLMs
---@param diff_content string Normalized diff content
---@return string fixed_content
function DiffParser:_fix_malformed_diff(diff_content)
    local lines = vim.split(diff_content, "\n")

    -- Check if we have any search marker at all
    local has_search_marker = false
    for _, line in ipairs(lines) do
        if self:_detect_marker_type(line) == "search" then
            has_search_marker = true
            break
        end
    end

    if has_search_marker then
        return diff_content
    end

    self.tracker:track_issue("MALFORMED_SEARCH_MARKER")

    -- Handle markdown code blocks
    local first_line = lines[1]
    if first_line and first_line:match("^%s*```") then
        table.insert(lines, 2, "<<<<<<< SEARCH")
        if self.config.track_issues then
            self.tracker:track_issue("MARKDOWN_NOISE")
        end
    else
        table.insert(lines, 1, "<<<<<<< SEARCH")
    end

    return table.concat(lines, "\n")
end

-- Parse fixed diff content into blocks
---@param diff_content string Fixed diff content
---@return ParsedBlock[]? blocks Parsed blocks (nil on error)
---@return string? error_message Error message if parsing failed
function DiffParser:_parse_blocks(diff_content)
    local lines = vim.split(diff_content, "\n")
    local blocks = {}
    local current_search = {}
    local current_replace = {}
    local state = "waiting" -- "waiting", "searching", "replacing"
    local block_counter = 1

    for line_num, line in ipairs(lines) do
        local marker_type, inline_content = self:_detect_marker_type(line, true)

        if marker_type == "search" then
            if state ~= "waiting" then
                return nil,
                    "Unexpected SEARCH marker at line "
                        .. line_num
                        .. " - expected SEPARATOR or REPLACE marker. If content to search or replace for contains <<<<<<< SEARCH, please escape it with a backslash like \\<<<<<<< SEARCH. SEARCH marker must be the first line of a block."
            end
            -- Start of search block
            state = "searching"
            current_search = {}

            -- Handle inline content on search marker line
            if inline_content and self.config.extract_inline_content then
                table.insert(current_search, inline_content)
            end
        elseif marker_type == "separator" then
            if state ~= "searching" then
                return nil,
                    "Unexpected separator at line "
                        .. line_num
                        .. " - expected SEARCH marker. If content to search or replace for contains ======, please escape it with a backslash like \\======. Separator must be between SEARCH and REPLACE markers."
            end
            -- Transition from search to replace
            state = "replacing"
            current_replace = {}
        elseif marker_type == "replace" then
            if state ~= "replacing" then
                return nil,
                    "Unexpected REPLACE marker at line "
                        .. line_num
                        .. " - expected REPLACE marker. If content to search or replace for contains >>>>>>> REPLACE, please escape it with a backslash like \\>>>>>> REPLACE. REPLACE marker must follow a SEARCH marker and a SEPARATOR."
            end
            -- End of replace block - create block
            state = "waiting"

            -- Handle inline content on replace marker line
            if inline_content and self.config.extract_inline_content then
                table.insert(current_replace, inline_content)
            end

            -- Create the block
            local search_content = table.concat(current_search, "\n")
            local replace_content = table.concat(current_replace, "\n")

            -- Skip empty blocks (unless it's intentional deletion)
            if search_content ~= "" or replace_content ~= "" then
                local block = {
                    search_content = search_content,
                    replace_content = replace_content,
                    block_id = "Block " .. block_counter,
                    search_lines = vim.deepcopy(current_search),
                    replace_lines = vim.deepcopy(current_replace),
                }
                table.insert(blocks, block)
                block_counter = block_counter + 1
            end
        elseif state == "searching" then
            -- Collect search content
            table.insert(current_search, self:unescape_markers(line))
        elseif state == "replacing" then
            -- Collect replace content
            table.insert(current_replace, self:unescape_markers(line))
        end
    end

    -- Handle incomplete blocks
    if state == "searching" and #current_search > 0 then
        return nil, "Incomplete search block - missing separator or replace section"
    end

    if state == "replacing" then
        return nil, "Incomplete replace block - missing replace marker"
    end

    if #blocks == 0 then
        return nil, "No valid SEARCH/REPLACE blocks found"
    end

    return blocks, nil
end

-- Detect marker type and extract inline content
---@param line string Line to analyze
---@param track boolean Track issues if true
---@return string? marker_type "search", "separator", "replace", or nil
---@return string? inline_content Content found on marker line
function DiffParser:_detect_marker_type(line, track)
    -- Search marker: minimum 5 < chars, optional spaces, case-insensitive SEARCH
    local search_arrows, search_spaces, search_keyword, search_content =
        line:match("^%s*(<<<<<+)(%s*)([Ss][Ee][Aa][Rr][Cc][Hh])(.*)$")

    if search_arrows then
        local inline_content = nil

        if self.config.extract_inline_content and search_content and search_content:match("%S") then
            -- Handle claude-4 case: "<<<<<<< SEARCH> content", use .- to handle cases with just >. If not the inline content becomes `>` and the first file line will be matched with >
            local claude_content = search_content:match("^>%s*(.-)$")
            if claude_content then
                if claude_content ~= "" then
                    inline_content = claude_content
                end
                if track then
                    self.tracker:track_issue("CLAUDE_MARKER_ISSUE", { inline_content = claude_content, line = line })
                end
            else
                -- Regular content after marker
                local regular_content = search_content:match("^%s*(.+)$")
                if regular_content and regular_content ~= "" then
                    inline_content = regular_content
                end
                if track then
                    self.tracker:track_issue("CONTENT_ON_MARKER_LINE", { inline_content = inline_content, line = line })
                end
            end
        end

        -- Track spacing issues
        if track then
            if search_spaces == "" then
                self.tracker:track_issue("MISSING_SPACES_IN_MARKERS")
            elseif #search_spaces > 1 then
                self.tracker:track_issue("EXTRA_SPACES_IN_MARKERS")
            end
            -- Track case issues
            if search_keyword ~= "SEARCH" then
                self.tracker:track_issue("CASE_MISMATCH_MARKERS")
            end
        end

        return "search", inline_content
    end

    -- Replace marker: minimum 5 > chars
    local replace_arrows, replace_spaces, replace_keyword, replace_trailing =
        line:match("^%s*(>>>>>+)(%s*)([Rr][Ee][Pp][Ll][Aa][Cc][Ee])(.*)$")

    if replace_arrows then
        local inline_content = nil

        -- Check for content AFTER the marker (trailing content)
        if self.config.extract_inline_content and replace_trailing and replace_trailing:match("%S") then
            inline_content = replace_trailing:match("^%s*(.-)%s*$") -- trim spaces
        end

        -- Track spacing and case issues
        if track then
            if replace_spaces == "" then
                self.tracker:track_issue("MISSING_SPACES_IN_MARKERS")
            elseif #replace_spaces > 1 then
                self.tracker:track_issue("EXTRA_SPACES_IN_MARKERS")
            end

            if replace_keyword ~= "REPLACE" then
                self.tracker:track_issue("CASE_MISMATCH_MARKERS")
            end
        end

        return "replace", inline_content
    end

    if line:match("^=======%s*$") then
        return "separator", nil
    end

    return nil, nil
end

-- Get comprehensive feedback including statistics
---@return string? feedback Complete feedback for LLM
function DiffParser:get_feedback()
    local parsing_feedback = self.tracker:get_llm_feedback()
    if parsing_feedback then
        return "## ISSUES WHILE PARSING DIFF\n" .. parsing_feedback
    end
end

function DiffParser:unescape_markers(line)
    local newline = line:gsub("^%s*\\<<<<<", "<<<<<<"):gsub("^%s*\\=====", "====="):gsub("^%s*\\>>>>>", ">>>>>")
    return newline
end

return DiffParser
