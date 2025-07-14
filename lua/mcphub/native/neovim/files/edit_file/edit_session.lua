-- EditSession - Main orchestrator for the editing workflow
-- Coordinates parsing, location, and UI components

---@class EditSession
---@field origin_winnr number Window number where the session started
---@field file_path string Path to the file being edited
---@field diff_content string Raw diff content from LLM
---@field config EditSessionConfig Configuration options
---@field parser DiffParser Parser instance
---@field locator BlockLocator Block locator instance
---@field located_blocks LocatedBlock[] Located blocks after parsing and locating
---@field ui EditUI? UI instance (created when needed)
---@field callbacks table Success/error callbacks
local EditSession = {}
EditSession.__index = EditSession

local Path = require("plenary.path")
local DEFAULT_CONFIG = {
    parser = {
        track_issues = true,
        extract_inline_content = true,
    },
    locator = {
        fuzzy_threshold = 0.8,
        enable_fuzzy_matching = true,
    },
    ui = {
        go_to_origin_on_complete = true,
        keybindings = {
            accept = ".", -- Accept current change
            reject = ",", -- Reject current change
            next = "n", -- Next diff
            prev = "p", -- Previous diff
            accept_all = "ga", -- Accept all remaining changes
            reject_all = "gr", -- Reject all remaining changes
        },
    },
    feedback = {
        include_parser_feedback = true,
        include_locator_feedback = true,
        include_ui_summary = true,
        ui = {
            include_session_summary = true,
            include_final_diff = true,
            send_diagnostics = true,
            wait_for_diagnostics = 500,
            diagnostic_severity = vim.diagnostic.severity.WARN, -- Only show warnings and above by default
        },
    },
}

-- Create new edit session
---@param file_path string Path to file to edit
---@param diff_content string Raw diff content
---@param config EditSessionConfig? Optional configuration
---@return EditSession
function EditSession.new(file_path, diff_content, config)
    local self = setmetatable({}, EditSession)

    self.file_path = file_path
    self.diff_content = diff_content
    self.config = vim.tbl_deep_extend("force", DEFAULT_CONFIG, config or {})

    self.origin_winnr = vim.api.nvim_get_current_win()
    -- Load components
    local DiffParser = require("mcphub.native.neovim.files.edit_file.diff_parser")
    local BlockLocator = require("mcphub.native.neovim.files.edit_file.block_locator")

    self.parser = DiffParser.new(self.config.parser)
    self.locator = BlockLocator.new(self.config.locator)

    return self
end

--- Get the content of the buffer if available or read from file
---@param path string Path to the file
---@param bufnr number? Buffer number to read from (if available)
---@return string content File content or nil if not found
function EditSession:get_file_content(path, bufnr)
    --INFO: unloaded buffers return empty lines
    if bufnr and vim.api.nvim_buf_is_valid(bufnr) and vim.api.nvim_buf_is_loaded(bufnr) then
        return table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
    end

    local file_path = Path:new(path)
    if file_path:exists() and file_path:is_file() then
        return file_path:read()
    end
    return ""
end

--- Start the editing session
---@param options table Options including on_success, on_error callbacks
function EditSession:start(options)
    self.callbacks = {
        on_success = options.on_success or function() end,
        on_error = options.on_error or function() end,
    }
    local buf_utils = require("mcphub.native.neovim.utils.buffer")
    local buf_info = buf_utils.find_buffer(self.file_path) or {}
    local file_content = self:get_file_content(self.file_path, buf_info.bufnr)
    local is_replacing_entire_file = options.replace_file_content ~= nil

    ---@type ParsedBlock[]
    local parsed_blocks = {}
    --- Needed to avoid parsing error when the file content has markers
    if is_replacing_entire_file then
        table.insert(parsed_blocks, {
            block_id = "Block 1",
            search_content = "",
            search_lines = {},
            replace_content = options.replace_file_content,
            replace_lines = vim.split(options.replace_file_content, "\n", { plain = true, trimempty = true }),
        }--[[@as ParsedBlock]])
    else
        local _parsed_blocks, parse_error = self.parser:parse(self.diff_content)
        if not _parsed_blocks then
            return self:_handle_error("Failed to parse diff: " .. parse_error)
        end
        parsed_blocks = _parsed_blocks
    end

    for _, block in ipairs(parsed_blocks) do
        if vim.trim(block.search_content) == "" then
            if #parsed_blocks > 1 then
                return self:_handle_error(
                    string.format(
                        "A Block with empty search content found, but multiple blocks are present in the diff. %s will replace the entire file. If you want to write the entire file, please use a single SEARCH/REPLACE block with empty SEARCH content. If you want to replace a section of the file, please provide non-whitespace SEARCH content.",
                        block.block_id
                    )
                )
            end
            is_replacing_entire_file = true
            break
        else
            -- If we are searching for something in a file that doesn't exist, we should not proceed
            if file_content == "" then
                return self:_handle_error(
                    string.format(
                        "Editing `%s` failed. The file does not exist. If you are using relative paths make sure the path is relative to the cwd or use an absolute path.",
                        self.file_path
                    )
                )
            end
        end
    end

    local located_blocks = self.locator:locate_all_blocks(parsed_blocks, file_content)
    self.located_blocks = located_blocks

    local failed_blocks = vim.tbl_filter(function(block)
        return not block.location_result.found
    end, located_blocks)
    if #failed_blocks > 0 then
        return self:_handle_error(
            string.format(
                "## Editing `%s` failed. No changes were made to the file. Couldn't find %d of %d block(s). Please see the <BESTMATCH/> content provided in the SEARCHING feedback.",
                self.file_path,
                #failed_blocks,
                #located_blocks
            )
        )
    end

    local EditUI = require("mcphub.native.neovim.files.edit_file.edit_ui")
    self.ui = EditUI.new(self.config.ui)

    self.ui:start_interactive_editing({
        interactive = options.interactive ~= false,
        is_replacing_entire_file = is_replacing_entire_file,
        origin_winnr = self.origin_winnr,
        file_path = self.file_path,
        located_blocks = self.located_blocks,
        original_content = file_content,
        on_complete = function()
            self:_generate_final_report(false, function(report)
                self.callbacks.on_success("# EDIT SESSION\n\n" .. report)
                self.ui:cleanup()
            end)
        end,
        on_cancel = function(reason)
            self:_generate_final_report(true, function(feedback_report)
                local final_report = string.format(
                    "# EDIT SESSION\n\n%s%s",
                    reason or "User rejected the changes to the file",
                    feedback_report ~= "" and ("\n\n" .. feedback_report) or ""
                )
                self.callbacks.on_error(final_report)
                self.ui:cleanup()
            end)
        end,
    })
end

-- Handle errors with comprehensive feedback
---@param error_msg string Error message
function EditSession:_handle_error(error_msg)
    self:_generate_final_report(true, function(feedback_report)
        local final_report = string.format(
            "# EDIT SESSION\n\n%s%s",
            error_msg or "User rejected the changes to the file",
            feedback_report ~= "" and ("\n\n" .. feedback_report) or ""
        )
        self.callbacks.on_error(final_report)
    end)
end

-- Generate final report by orchestrating feedback from all components
---@param is_cancelled boolean Whether the session was cancelled
---@param on_report_ready function Callback to receive the final report
function EditSession:_generate_final_report(is_cancelled, on_report_ready)
    local feedback_parts = {}
    local feedback_config = self.config.feedback

    -- Get Parser Feedback
    if feedback_config.include_parser_feedback then
        local parser_feedback = self.parser:get_feedback()
        if parser_feedback then
            table.insert(feedback_parts, parser_feedback)
        end
    end

    -- Get Locator Feedback
    if feedback_config.include_locator_feedback then
        local locator_feedback = self.locator:get_feedback(self.located_blocks)
        if locator_feedback then
            table.insert(feedback_parts, locator_feedback)
        end
    end

    -- Get UI Summary (Asynchronous due to waiting for diagnostics)
    if feedback_config.include_ui_summary and self.ui and not is_cancelled then
        self.ui:get_summary(feedback_config.ui, function(ui_summary)
            if ui_summary and ui_summary ~= "" then
                table.insert(feedback_parts, ui_summary)
            end
            on_report_ready(table.concat(feedback_parts, "\n\n"))
        end)
    else
        on_report_ready(table.concat(feedback_parts, "\n\n"))
    end
end

return EditSession
