-- Type definitions for the Editor system
-- All classes reference these unified type structures

local M = {}

-- Enums for type safety and better IntelliSense
---@enum OverallMatchType
M.OVERALL_MATCH_TYPE = {
    exact = "exact",
    exact_whitespace = "exact_whitespace",
    fuzzy_high = "fuzzy_high",
    fuzzy_medium = "fuzzy_medium",
    fuzzy_low = "fuzzy_low",
}

---@enum LineMatchType
M.LINE_MATCH_TYPE = {
    exact = "exact",
    exact_whitespace = "exact_whitespace",
    normalized = "normalized",
    punctuation = "punctuation",
    case_insensitive = "case_insensitive",
    fuzzy_high = "fuzzy_high",
    fuzzy_medium = "fuzzy_medium",
    fuzzy_low = "fuzzy_low",
    no_match = "no_match",
}

---@enum SearchMethod
M.SEARCH_METHOD = {
    exact_scan = "exact_scan",
    fuzzy_search = "fuzzy_search",
    middle_out = "middle_out",
    linear = "linear",
}

---@enum SearchStrategy
M.SEARCH_STRATEGY = {
    auto = "auto",
    linear = "linear",
    middle_out = "middle_out",
}

---@enum DiffHunkType
M.DIFF_HUNK_TYPE = {
    addition = "addition",
    deletion = "deletion",
    change = "change",
}

---@enum BlockStatus
M.BLOCK_STATUS = {
    ready = "ready",
    failed = "failed",
    skipped = "skipped",
}

---@enum DifferenceType
M.DIFFERENCE_TYPE = {
    quote_style = "quote_style",
    whitespace = "whitespace",
    case = "case",
    punctuation = "punctuation",
    html_entities = "html_entities",
}

---@class BlockLocationResult
---@field found boolean Whether block was located in file
---@field start_line integer? 1-based start line (nil if not found)
---@field end_line integer? 1-based end line (nil if not found)
---@field overall_score number Overall match score (0.0-1.0)
---@field overall_match_type OverallMatchType Match type classification
---@field confidence integer Overall confidence percentage (0-100)
---@field found_content string? Actual content found in file
---@field found_lines string[]? Actual lines found in file
---@field line_details LineMatchDetail[] Per-line match information
---@field search_metadata SearchMetadata Performance and method info
---@field error string? Error message if not found

---@class LineMatchDetail
---@field line_number integer Absolute line number in file
---@field expected_line string What we were searching for
---@field found_line string What was actually in the file
---@field line_score number Match score for this line (0.0-1.0)
---@field line_match_type LineMatchType Match type for this specific line
---@field differences DifferenceType[]? List of difference types found

---@class SearchMetadata
---@field method SearchMethod Search method used to find the block
---@field iterations integer Number of search iterations performed
---@field search_strategy SearchStrategy Search strategy that was employed
---@field search_bounds integer[] Start and end bounds used for search
---@field early_termination boolean Whether search stopped early due to good match

---@class ParsedBlock
---@field search_content string Exact content to find
---@field replace_content string Replacement content
---@field block_id string Unique identifier for this block
---@field search_lines string[] Split search content into lines
---@field replace_lines string[] Split replace content into lines

---@class LocatedBlock
---@field search_content string Exact content to find
---@field replace_content string Replacement content
---@field block_id string Unique identifier for this block
---@field search_lines string[] Split search content into lines
---@field replace_lines string[] Split replace content into lines
---@field location_result BlockLocationResult Complete location information
---@field applied_start_line integer? 1-based start line in file (nil if not found)
---@field applied_end_line integer? 1-based end line in file (nil if not found)
---@field applied_hunk_ranges table<integer, integer>[]? List of {start_line, end_line} pairs for applied hunks
---@field old_ext_id integer? External mark ID for old content (if applicable) -- DEPRECATED (replaced by hunk_extmarks)
---@field new_ext_id integer? External mark ID for new content (if applicable) -- DEPRECATED (replaced by hunk_extmarks)

---@class DiffHunk
---@field hunk_id string Unique identifier for this hunk
---@field parent_id string Parent block ID if this hunk is part of a larger block
---@field old_lines string[] Lines being removed/changed
---@field new_lines string[] Lines being added/changed
---@field extmark_id integer? External mark ID for this hunk (nil if not set)
---@field del_extmark_id integer? External mark ID for virtual lines added to this hunk
---@field deletion_position integer? If this hunk is a deletion, the line number where it was removed (nil if not a deletion)
---@field type DiffHunkType Type of change in this hunk
---@field applied_start_line integer 1-based start line in file (nil if not applied)
---@field applied_end_line integer 1-based end line in file (nil if not applied)
---@field confidence integer Confidence percentage for this hunk (0-100)

---@class FuzzyHighlight
---@field line_num integer Absolute line number in file
---@field highlight_type string Highlight group name
---@field expected string What was expected
---@field actual string What was actually found
---@field reason string Reason for mismatch
---@field char_positions integer[]? Character positions that differ

---@class ContextInfo
---@field start_line integer Context start line for UI display
---@field end_line integer Context end line for UI display
---@field surrounding_lines string[]? Additional context lines if needed

---@class ParsingIssue
---@field type string Issue type identifier
---@field details table Issue-specific details
---@field timestamp integer When the issue was tracked
---@field severity string "warning" | "error" | "info"
---@field description string Human-readable description of the issue
---@field fix string Suggested fix or action to take
---@field llm_guidance string Guidance for LLM feedback on this issue

---@class EditSessionConfig
---@field parser ParserConfig? Parser-specific configuration
---@field locator LocatorConfig? Block locator configuration
---@field analyzer AnalyzerConfig? Diff analyzer configuration
---@field ui UIConfig? UI-specific configuration
---@field feedback table Feedback configuration for LLM

---@class ParserConfig
---@field track_issues boolean Track parsing issues for LLM feedback
---@field extract_inline_content boolean Handle content on marker lines

---@class LocatorConfig
---@field fuzzy_threshold number Minimum similarity score for fuzzy matches (0.0-1.0)
---@field enable_fuzzy_matching boolean Allow fuzzy matching when exact fails

---@class AnalyzerConfig
---@field diff_algorithm string "patience" | "minimal" | "histogram"
---@field context_lines integer Number of context lines to include
---@field show_char_diff boolean Show character-level differences

---@class UIKeybindings
---@field accept string Key to accept changes
---@field reject string Key to reject changes
---@field next string Key to navigate to next block
---@field prev string Key to navigate to previous block
---@field accept_all string Key to accept all changes
---@field reject_all string Key to reject all changes

---@class UIConfig
---@field go_to_origin_on_complete boolean Jump back to original file on completion
---@field keybindings UIKeybindings Custom keybindings for UI actions
return M
