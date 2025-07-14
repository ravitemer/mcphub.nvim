-- Issue Tracker for Editor Operations
-- Tracks parsing and processing issues and provides feedback to LLMs

local M = {}

-- Issue types that can be tracked and reported back to LLM
M.ISSUE_TYPES = {
    EXTRA_SPACES_IN_MARKERS = {
        description = "Extra spaces found in search/replace markers",
        fix = "Normalized marker spacing",
        llm_guidance = "Use exactly one space: '<<<<<<< SEARCH' not '<<<<<<<  SEARCH'",
        severity = "warning",
    },

    CASE_MISMATCH_MARKERS = {
        description = "Inconsistent case in SEARCH/REPLACE keywords",
        fix = "Converted to uppercase",
        llm_guidance = "Always use uppercase: 'SEARCH' and 'REPLACE'",
        severity = "warning",
    },

    MISSING_SPACES_IN_MARKERS = {
        description = "No space between markers and keywords",
        fix = "Added missing space",
        llm_guidance = "Use space: '<<<<<<< SEARCH' not '<<<<<<<SEARCH'",
        severity = "warning",
    },

    MARKDOWN_NOISE = {
        description = "Markdown code blocks around diff content",
        fix = "Stripped markdown formatting",
        llm_guidance = "Don't wrap diff blocks in markdown code blocks",
        severity = "info",
    },

    MALFORMED_SEARCH_MARKER = {
        description = "Missing or malformed SEARCH marker",
        fix = "Added missing SEARCH marker",
        llm_guidance = "Always start blocks with '<<<<<<< SEARCH'",
        severity = "error",
    },

    FUZZY_MATCH_WARNING = {
        description = "Block found with fuzzy matching instead of exact match",
        fix = "Applied fuzzy matching with confidence score",
        llm_guidance = "Consider using exact content from the file to avoid fuzzy matching",
        severity = "info",
    },

    BLOCK_LOCATION_FAILED = {
        description = "Failed to locate block content in file",
        fix = "Block skipped",
        llm_guidance = "Ensure the search content exists exactly in the target file",
        severity = "error",
    },
    CONTENT_ON_MARKER_LINE = function(details)
        return {
            description = string.format("`<<<<<<< SEARCH` marker line contains content: `%s`", details.inline_content),
            fix = "Removed content on the marker line and used it as first line in the SEARCH block.",
            llm_guidance = "`<<<<<<< SEARCH` marker line should not contain any content, only the marker itself",
            severity = "warning",
        }
    end,
    CLAUDE_MARKER_ISSUE = function(details)
        local inline_content = details.inline_content
        local line = details.line
        return {
            description = string.format("`<<<<<<< SEARCH` marker line is not EXACT. `%s` found instead", line),
            fix = "Removed `>`"
                .. (
                    inline_content ~= "" and " and content on that line is used as first line in the SEARCH block."
                    or ""
                ),
            llm_guidance = "`<<<<<<< SEARCH` marker line should be EXACT without any other characters like `>` or other content on the marker lines",
            severity = "warning",
        }
    end,
}

---@class IssueTracker
---@field issues_found ParsingIssue[] List of tracked issues
local IssueTracker = {}
IssueTracker.__index = IssueTracker

-- Create a new issue tracker instance
---@return IssueTracker
function M.new()
    local self = setmetatable({}, IssueTracker)
    self.issues_found = {}
    return self
end

-- Track a new issue
---@param issue_type string Issue type from ISSUE_TYPES
---@param details table? Issue-specific details
function IssueTracker:track_issue(issue_type, details)
    if not M.ISSUE_TYPES[issue_type] then
        error("Unknown issue type: " .. tostring(issue_type))
    end
    local issue_info = M.ISSUE_TYPES[issue_type]
    if type(issue_info) == "function" then
        issue_info = issue_info(details)
    end
    if issue_info then
        table.insert(self.issues_found, {
            type = issue_type,
            details = details or {},
            timestamp = os.time(),
            severity = issue_info.severity,
            description = issue_info.description,
            fix = issue_info.fix,
            llm_guidance = issue_info.llm_guidance,
        })
    end
end

-- Check if any issues were found
---@return boolean has_issues
function IssueTracker:has_issues()
    return #self.issues_found > 0
end

-- Generate LLM feedback with categorized issues
---@return string? feedback Formatted feedback for LLM (nil if no issues)
function IssueTracker:get_llm_feedback()
    if #self.issues_found == 0 then
        return nil
    end

    local parts = {}

    for _, issue in ipairs(self.issues_found) do
        local str = string.format(
            "### %s\nIssue Encountered: %s\nResolved By Editor: %s\nFuture Guidance: %s",
            issue.severity:upper(),
            issue.description,
            issue.fix,
            issue.llm_guidance
        )
        table.insert(parts, str)
    end
    return #parts > 0 and table.concat(parts, "\n\n") or nil
end

-- Clear all tracked issues
function IssueTracker:clear()
    self.issues_found = {}
end

return M
