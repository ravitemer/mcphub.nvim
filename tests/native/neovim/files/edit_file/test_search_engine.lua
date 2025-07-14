-- Tests for SearchEngine - Basic Search Functionality
local new_set = MiniTest.new_set
local expect, eq = MiniTest.expect, MiniTest.expect.equality

local T = new_set({
    hooks = {
        pre_case = function()
            -- Load required modules for each test
            local SearchEngine = require("mcphub.native.neovim.files.edit_file.search_engine")
            _G.types = require("mcphub.native.neovim.files.edit_file.types")

            -- Create a fresh search engine instance with default config
            _G.search_engine = SearchEngine.new()
        end,
        post_case = function()
            -- Clean up
            _G.search_engine = nil
            _G.types = nil
        end,
    },
})

-- Group 1: Basic Search Functionality
T["basic_search"] = new_set()

T["basic_search"]["single_exact_match"] = function()
    local search_lines = { "local x = 1", "local y = 2" }
    local file_lines = {
        "-- Header comment",
        "local x = 1",
        "local y = 2",
        "-- Footer comment",
    }

    local result = _G.search_engine:locate_block_in_file(search_lines, file_lines)

    -- Should find exact match
    eq(result.found, true)
    eq(result.start_line, 2)
    eq(result.end_line, 3)
    eq(result.overall_match_type, _G.types.OVERALL_MATCH_TYPE.exact)
    eq(result.overall_score, 1.0)
    eq(result.confidence, 100)

    -- Check found content
    eq(result.found_content, "local x = 1\nlocal y = 2")
    eq(vim.deep_equal(result.found_lines, { "local x = 1", "local y = 2" }), true)

    -- Check line details
    eq(#result.line_details, 2)
    eq(result.line_details[1].line_match_type, _G.types.LINE_MATCH_TYPE.exact)
    eq(result.line_details[2].line_match_type, _G.types.LINE_MATCH_TYPE.exact)
end

T["basic_search"]["single_line_match"] = function()
    local search_lines = { "function test()" }
    local file_lines = {
        "local x = 1",
        "function test()",
        "    return true",
        "end",
    }

    local result = _G.search_engine:locate_block_in_file(search_lines, file_lines)

    eq(result.found, true)
    eq(result.start_line, 2)
    eq(result.end_line, 2)
    eq(result.overall_match_type, _G.types.OVERALL_MATCH_TYPE.exact)
    eq(result.found_content, "function test()")
end

T["basic_search"]["match_at_beginning_of_file"] = function()
    local search_lines = { "#!/bin/bash", "echo 'hello'" }
    local file_lines = {
        "#!/bin/bash",
        "echo 'hello'",
        "echo 'world'",
        "exit 0",
    }

    local result = _G.search_engine:locate_block_in_file(search_lines, file_lines)

    eq(result.found, true)
    eq(result.start_line, 1)
    eq(result.end_line, 2)
    eq(result.overall_match_type, _G.types.OVERALL_MATCH_TYPE.exact)
end

T["basic_search"]["match_at_end_of_file"] = function()
    local search_lines = { "return result", "end" }
    local file_lines = {
        "function calculate()",
        "    local result = 42",
        "    return result",
        "end",
    }

    local result = _G.search_engine:locate_block_in_file(search_lines, file_lines)

    eq(result.found, true)
    eq(result.start_line, 3)
    eq(result.end_line, 4)
    eq(result.overall_match_type, _G.types.OVERALL_MATCH_TYPE.exact_whitespace)
end

T["basic_search"]["entire_file_match"] = function()
    local search_lines = { "line1", "line2", "line3" }
    local file_lines = { "line1", "line2", "line3" }

    local result = _G.search_engine:locate_block_in_file(search_lines, file_lines)

    eq(result.found, true)
    eq(result.start_line, 1)
    eq(result.end_line, 3)
    eq(result.overall_match_type, _G.types.OVERALL_MATCH_TYPE.exact)
    eq(result.found_content, "line1\nline2\nline3")
end

T["basic_search"]["no_match_found"] = function()
    local search_lines = { "nonexistent function", "also not found" }
    local file_lines = {
        "function real_function()",
        "    return true",
        "end",
    }

    local result = _G.search_engine:locate_block_in_file(search_lines, file_lines)

    eq(result.found, false)
    eq(type(result.error), "string")
    expect.equality(result.error:match("No suitable match found") ~= nil, true)
end

T["basic_search"]["search_longer_than_file"] = function()
    local search_lines = { "line1", "line2", "line3", "line4" }
    local file_lines = { "line1", "line2" } -- Only 2 lines

    local result = _G.search_engine:locate_block_in_file(search_lines, file_lines)

    eq(result.found, false)
    eq(type(result.error), "string")
    expect.equality(result.error:match("SEARCH block lines more than file lines.") ~= nil, true)
end

T["basic_search"]["empty_search_lines"] = function()
    local search_lines = {}
    local file_lines = { "line1", "line2", "line3" }

    local result = _G.search_engine:locate_block_in_file(search_lines, file_lines)

    eq(result.found, true)
    eq(result.found_lines, file_lines)
end

T["basic_search"]["empty_file"] = function()
    local search_lines = { "some content" }
    local file_lines = {}

    local result = _G.search_engine:locate_block_in_file(search_lines, file_lines)

    eq(result.found, false)
    eq(type(result.error), "string")
end

T["basic_search"]["whitespace_exact_match"] = function()
    local search_lines = { "  local x = 1  ", "    local y = 2" }
    local file_lines = {
        "function test()",
        "  local x = 1  ",
        "    local y = 2",
        "end",
    }

    local result = _G.search_engine:locate_block_in_file(search_lines, file_lines)

    eq(result.found, true)
    eq(result.start_line, 2)
    eq(result.end_line, 3)
    eq(result.overall_match_type, _G.types.OVERALL_MATCH_TYPE.exact)
end

T["basic_search"]["multiple_potential_matches_chooses_best"] = function()
    -- File with two similar sections, search engine should find the exact one
    local search_lines = { "local x = 1", "local y = 2" }
    local file_lines = {
        "-- First section",
        "local x = 1",
        "local y = 2",
        "-- Middle section",
        "local x = 1",
        "local y = 3", -- Different from search
        "-- End section",
    }

    local result = _G.search_engine:locate_block_in_file(search_lines, file_lines)

    eq(result.found, true)
    eq(result.start_line, 2) -- Should choose the first exact match
    eq(result.end_line, 3)
    eq(result.overall_match_type, _G.types.OVERALL_MATCH_TYPE.exact)
    eq(result.overall_score, 1.0)
end

T["basic_search"]["line_details_accuracy"] = function()
    local search_lines = { "line one", "line two" }
    local file_lines = {
        "prefix",
        "line one",
        "line two",
        "suffix",
    }

    local result = _G.search_engine:locate_block_in_file(search_lines, file_lines)

    eq(result.found, true)
    eq(#result.line_details, 2)

    -- Check first line detail
    local detail1 = result.line_details[1]
    eq(detail1.line_number, 2)
    eq(detail1.expected_line, "line one")
    eq(detail1.found_line, "line one")
    eq(detail1.line_score, 1.0)
    eq(detail1.line_match_type, _G.types.LINE_MATCH_TYPE.exact)

    -- Check second line detail
    local detail2 = result.line_details[2]
    eq(detail2.line_number, 3)
    eq(detail2.expected_line, "line two")
    eq(detail2.found_line, "line two")
    eq(detail2.line_score, 1.0)
    eq(detail2.line_match_type, _G.types.LINE_MATCH_TYPE.exact)
end

T["basic_search"]["reset_used_ranges_between_searches"] = function()
    -- Test that used ranges don't persist between different locate calls
    local search_lines = { "common line" }
    local file_lines = { "common line", "other content" }

    -- First search
    local result1 = _G.search_engine:locate_block_in_file(search_lines, file_lines)
    eq(result1.found, true)
    eq(result1.start_line, 1)

    -- Reset and search again - should find the same location
    _G.search_engine:reset_used_ranges()
    local result2 = _G.search_engine:locate_block_in_file(search_lines, file_lines)
    eq(result2.found, true)
    eq(result2.start_line, 1) -- Should find the same location again
end

-- Group 2: Fuzzy Matching and Scoring
T["fuzzy_matching"] = new_set()

T["fuzzy_matching"]["exact_whitespace_match"] = function()
    local search_lines = { "local x = 1", "local y = 2" }
    local file_lines = {
        "function test()",
        "  local x = 1  ", -- Extra spaces
        "local y = 2", -- Different indentation
        "end",
    }

    local result = _G.search_engine:locate_block_in_file(search_lines, file_lines)

    eq(result.found, true)
    eq(result.start_line, 2)
    eq(result.end_line, 3)
    eq(result.overall_match_type, _G.types.OVERALL_MATCH_TYPE.exact_whitespace)
    eq(result.overall_score >= 0.99, true)

    -- Check line details show whitespace differences
    eq(result.line_details[1].line_match_type, _G.types.LINE_MATCH_TYPE.exact_whitespace)
    eq(result.line_details[2].line_match_type, _G.types.LINE_MATCH_TYPE.exact)
end

T["fuzzy_matching"]["html_entities_normalization"] = function()
    local search_lines = { "value < threshold && valid" }
    local file_lines = {
        "if condition:",
        "    value &lt; threshold &amp;&amp; valid", -- HTML entities
        "    process()",
    }

    local result = _G.search_engine:locate_block_in_file(search_lines, file_lines)

    eq(result.found, true)
    eq(result.start_line, 2)
    eq(result.overall_match_type, _G.types.OVERALL_MATCH_TYPE.fuzzy_high)
    expect.equality(result.overall_score >= 0.85, true)
end

T["fuzzy_matching"]["case_insensitive_match"] = function()
    local search_lines = { "FUNCTION testFunction()", "RETURN result" }
    local file_lines = {
        "// Code block",
        "function testFunction()",
        "return result",
        "}",
    }

    local result = _G.search_engine:locate_block_in_file(search_lines, file_lines)

    eq(result.found, true)
    eq(result.start_line, 2)
    eq(result.end_line, 3)
    expect.equality(
        result.overall_match_type == _G.types.OVERALL_MATCH_TYPE.fuzzy_high
            or result.overall_match_type == _G.types.OVERALL_MATCH_TYPE.fuzzy_medium,
        true
    )
    expect.equality(result.overall_score >= 0.70, true)
end

T["fuzzy_matching"]["high_similarity_fuzzy_match"] = function()
    local search_lines = { "function calculateResult(input)" }
    local file_lines = {
        "class Calculator:",
        "    function calculateResults(input)", -- One character different
        "        return process(input)",
    }

    local result = _G.search_engine:locate_block_in_file(search_lines, file_lines)

    eq(result.found, true)
    eq(result.start_line, 2)
    eq(result.overall_match_type, _G.types.OVERALL_MATCH_TYPE.fuzzy_high)
    expect.equality(result.overall_score >= 0.85, true)
    expect.equality(result.overall_score < 1.0, true)
end

T["fuzzy_matching"]["medium_similarity_fuzzy_match"] = function()
    local search_lines = { "function processData(input)", "return output" }
    local file_lines = {
        "// Processing module",
        "function processData(param)", -- Similar but different
        "return output;", -- Similar but different
        "end",
    }

    local result = _G.search_engine:locate_block_in_file(search_lines, file_lines)

    eq(result.found, true)
    eq(result.start_line, 2)
    eq(result.end_line, 3)
    expect.equality(
        result.overall_match_type == _G.types.OVERALL_MATCH_TYPE.fuzzy_medium
            or result.overall_match_type == _G.types.OVERALL_MATCH_TYPE.fuzzy_high,
        true
    )
    expect.equality(result.overall_score >= 0.80, true)
end

T["fuzzy_matching"]["low_similarity_match"] = function()
    local search_lines = { "function oldFunction()", "  return oldValue" }
    local file_lines = {
        "class NewClass:",
        "  method newMethod():", -- Very different
        "    return newResult", -- Very different
        "  end",
    }

    local result = _G.search_engine:locate_block_in_file(search_lines, file_lines)

    -- May or may not find depending on fuzzy threshold configuration
    if result.found then
        expect.equality(
            result.overall_match_type == _G.types.OVERALL_MATCH_TYPE.fuzzy_low
                or result.overall_match_type == _G.types.OVERALL_MATCH_TYPE.fuzzy_medium,
            true
        )
        expect.equality(result.overall_score < 0.85, true)
    else
        expect.equality(result.error:match("No suitable match found") ~= nil, true)
    end
end

T["fuzzy_matching"]["below_fuzzy_threshold_no_match"] = function()
    local search_lines = { "completely different content", "nothing similar here" }
    local file_lines = {
        "xyz abc 123",
        "totally unrelated code",
        "end",
    }

    local result = _G.search_engine:locate_block_in_file(search_lines, file_lines)

    eq(result.found, false)
    expect.equality(result.error:match("No suitable match found") ~= nil, true)

    -- Should still provide some scoring information
    expect.equality(type(result.overall_score), "number")
    expect.equality(result.overall_score < 0.8, true) -- Below fuzzy threshold
end

T["fuzzy_matching"]["mixed_line_quality_scoring"] = function()
    local search_lines = {
        "function test()", -- Will match exactly
        "  return value", -- Will match with whitespace differences
    }
    local file_lines = {
        "// Test function",
        "function test()", -- Exact match
        "return value", -- Whitespace difference
        "end",
    }

    local result = _G.search_engine:locate_block_in_file(search_lines, file_lines)

    eq(result.found, true)
    eq(result.start_line, 2)
    eq(result.end_line, 3)

    -- Should classify as exact_whitespace due to second line
    eq(result.overall_match_type, _G.types.OVERALL_MATCH_TYPE.exact_whitespace)

    -- Check individual line scoring
    eq(result.line_details[1].line_match_type, _G.types.LINE_MATCH_TYPE.exact)
    eq(result.line_details[1].line_score, 1.0)
    eq(result.line_details[2].line_match_type, _G.types.LINE_MATCH_TYPE.exact_whitespace)
    eq(result.line_details[2].line_score, 0.99)
end

T["fuzzy_matching"]["early_termination_on_excellent_fuzzy"] = function()
    -- Test that very good fuzzy matches can trigger early termination
    local search_lines = { "function process(data)" }
    local file_lines = {
        "other function",
        "function process( data )", -- Excellent match with just whitespace diff
        "more content",
        "function process(info)", -- Another potential match
    }

    local result = _G.search_engine:locate_block_in_file(search_lines, file_lines)

    eq(result.found, true)
    eq(result.start_line, 2) -- Should find the better match
    expect.equality(result.overall_score >= 0.95, true) -- Very high score
end

T["fuzzy_matching"]["line_detail_differences_tracking"] = function()
    local search_lines = { 'print("hello")', "RETURN value" }
    local file_lines = {
        "function test():",
        "print('hello')", -- Quote style difference
        "return value", -- Case difference
        "end",
    }

    local result = _G.search_engine:locate_block_in_file(search_lines, file_lines)

    eq(result.found, true)
    eq(#result.line_details, 2)

    -- Check that differences are detected and tracked
    local detail1 = result.line_details[1]
    expect.equality(#detail1.differences > 0, true)

    local detail2 = result.line_details[2]
    expect.equality(#detail2.differences > 0, true)
    expect.equality(vim.tbl_contains(detail2.differences, _G.types.DIFFERENCE_TYPE.case), true)
end

T["fuzzy_matching"]["punctuation_normalization"] = function()
    local search_lines = { "func(arg1,arg2,arg3)" }
    local file_lines = {
        "// Function call",
        "func( arg1, arg2, arg3 )", -- Spacing differences
        "end",
    }

    local result = _G.search_engine:locate_block_in_file(search_lines, file_lines)

    eq(result.found, true)
    eq(result.start_line, 2)
    expect.equality(
        result.overall_match_type == _G.types.OVERALL_MATCH_TYPE.exact_whitespace
            or result.overall_match_type == _G.types.OVERALL_MATCH_TYPE.fuzzy_high,
        true
    )
end

T["fuzzy_matching"]["multiline_block_average_scoring"] = function()
    local search_lines = {
        "function test()", -- Exact match
        "  local x = 1", -- Whitespace difference
        "  return x + 1", -- Slight content difference (x + 2 in file)
    }
    local file_lines = {
        "class TestClass:",
        "  function test()", -- Exact
        "local x = 1", -- Whitespace diff
        "return x + 2", -- Content diff
        "end",
    }

    local result = _G.search_engine:locate_block_in_file(search_lines, file_lines)

    eq(result.found, true)
    eq(result.start_line, 2)
    eq(result.end_line, 4)

    -- Overall score should be average of individual line scores
    local line_scores = {}
    for _, detail in ipairs(result.line_details) do
        table.insert(line_scores, detail.line_score)
    end

    local expected_avg = (line_scores[1] + line_scores[2] + line_scores[3]) / 3
    expect.equality(math.abs(result.overall_score - expected_avg) < 0.01, true)
end

T["fuzzy_matching"]["custom_fuzzy_threshold_respected"] = function()
    -- Test with a more restrictive fuzzy threshold
    local restrictive_engine = require("mcphub.native.neovim.files.edit_file.search_engine").new({
        fuzzy_threshold = 0.95,
        enable_fuzzy_matching = true,
    })

    local search_lines = { "function calculateValue(input)" }
    local file_lines = {
        "other content",
        "function calculateValues(input)", -- Slight difference
        "more content",
    }

    local result = restrictive_engine:locate_block_in_file(search_lines, file_lines)

    -- With high threshold, this might not match
    if not result.found then
        expect.equality(result.error:match("No suitable match found") ~= nil, true)
    else
        -- If it does match, score should be very high
        expect.equality(result.overall_score >= 0.95, true)
    end
end

-- Group 3: Duplicate Block Handling (Used Ranges)
T["duplicate_handling"] = new_set()

T["duplicate_handling"]["simple_used_range_tracking"] = function()
    local search_lines = { "duplicate line" }
    local file_lines = {
        "duplicate line", -- First occurrence
        "other content",
        "duplicate line", -- Second occurrence
        "more content",
    }

    -- First search should find first occurrence
    local result1 = _G.search_engine:locate_block_in_file(search_lines, file_lines)

    eq(result1.found, true)
    eq(result1.start_line, 1)
    eq(result1.end_line, 1)

    -- Second search should find second occurrence (first is now used)
    local result2 = _G.search_engine:locate_block_in_file(search_lines, file_lines)

    eq(result2.found, true)
    eq(result2.start_line, 3)
    eq(result2.end_line, 3)

    -- Third search should fail (both occurrences used)
    local result3 = _G.search_engine:locate_block_in_file(search_lines, file_lines)

    eq(result3.found, false)
    expect.equality(result3.error:match("No suitable match found") ~= nil, true)
end

T["duplicate_handling"]["multiline_block_range_tracking"] = function()
    local search_lines = { "function test()", "  return true", "end" }
    local file_lines = {
        "-- First function",
        "function test()",
        "  return true",
        "end",
        "-- Second function",
        "function test()",
        "  return true",
        "end",
        "-- End",
    }

    -- First search
    local result1 = _G.search_engine:locate_block_in_file(search_lines, file_lines)
    eq(result1.found, true)
    eq(result1.start_line, 2)
    eq(result1.end_line, 4)

    -- Second search should find the second occurrence
    local result2 = _G.search_engine:locate_block_in_file(search_lines, file_lines)
    eq(result2.found, true)
    eq(result2.start_line, 6)
    eq(result2.end_line, 8)
end

T["duplicate_handling"]["overlapping_range_prevention"] = function()
    local search_lines1 = { "line 2", "line 3" }
    local search_lines2 = { "line 3", "line 4" }
    local file_lines = {
        "line 1",
        "line 2", -- Lines 2-3 will be used first
        "line 3", -- This line overlaps
        "line 4",
        "line 5",
    }

    local SearchEngine = require("mcphub.native.neovim.files.edit_file.search_engine")
    _G.search_engine = SearchEngine.new({
        enable_fuzzy_matching = false, -- Disable fuzzy for this test
        used_ranges = {}, -- Reset used ranges
    })
    -- First search uses lines 2-3
    local result1 = _G.search_engine:locate_block_in_file(search_lines1, file_lines)
    eq(result1.found, true)
    eq(result1.start_line, 2)
    eq(result1.end_line, 3)

    -- Second search wants lines 3-4, but line 3 is already used
    -- Should fail due to overlap
    local result2 = _G.search_engine:locate_block_in_file(search_lines2, file_lines)
    eq(result2.found, false)
    expect.equality(result2.error:match("No suitable match found") ~= nil, true)
end

T["duplicate_handling"]["non_overlapping_adjacent_blocks"] = function()
    local search_lines1 = { "block 1 line 1", "block 1 line 2" }
    local search_lines2 = { "block 2 line 1", "block 2 line 2" }
    local file_lines = {
        "header",
        "block 1 line 1", -- Lines 2-3
        "block 1 line 2",
        "block 2 line 1", -- Lines 4-5 (adjacent, no overlap)
        "block 2 line 2",
        "footer",
    }

    -- First search
    local result1 = _G.search_engine:locate_block_in_file(search_lines1, file_lines)
    eq(result1.found, true)
    eq(result1.start_line, 2)
    eq(result1.end_line, 3)

    -- Second search should succeed (no overlap)
    local result2 = _G.search_engine:locate_block_in_file(search_lines2, file_lines)
    eq(result2.found, true)
    eq(result2.start_line, 4)
    eq(result2.end_line, 5)
end

T["duplicate_handling"]["reset_used_ranges"] = function()
    local search_lines = { "common content" }
    local file_lines = {
        "common content",
        "other stuff",
        "common content",
    }

    -- Use first occurrence
    local result1 = _G.search_engine:locate_block_in_file(search_lines, file_lines)
    eq(result1.found, true)
    eq(result1.start_line, 1)

    -- Use second occurrence
    local result2 = _G.search_engine:locate_block_in_file(search_lines, file_lines)
    eq(result2.found, true)
    eq(result2.start_line, 3)

    -- Third search should fail
    local result3 = _G.search_engine:locate_block_in_file(search_lines, file_lines)
    eq(result3.found, false)

    -- Reset ranges and try again
    _G.search_engine:reset_used_ranges()
    local result4 = _G.search_engine:locate_block_in_file(search_lines, file_lines)
    eq(result4.found, true)
    eq(result4.start_line, 1) -- Should find first occurrence again
end

T["duplicate_handling"]["complex_overlapping_scenarios"] = function()
    local file_lines = {
        "line 1",
        "line 2", -- Block A: lines 2-4
        "line 3",
        "line 4",
        "line 5", -- Block B: lines 5-6 (adjacent to A)
        "line 6",
        "line 7", -- Block C: lines 7-9
        "line 8",
        "line 9",
    }

    -- Use block A (lines 2-4)
    local result_a = _G.search_engine:locate_block_in_file({ "line 2", "line 3", "line 4" }, file_lines)
    eq(result_a.found, true)
    eq(result_a.start_line, 2)
    eq(result_a.end_line, 4)

    -- Use block C (lines 7-9)
    local result_c = _G.search_engine:locate_block_in_file({ "line 7", "line 8", "line 9" }, file_lines)
    eq(result_c.found, true)
    eq(result_c.start_line, 7)
    eq(result_c.end_line, 9)

    -- Block B should still be available (lines 5-6)
    local result_b = _G.search_engine:locate_block_in_file({ "line 5", "line 6" }, file_lines)
    eq(result_b.found, true)
    eq(result_b.start_line, 5)
    eq(result_b.end_line, 6)

    -- Now try to use a block that overlaps with A (should fail)
    local result_overlap = _G.search_engine:locate_block_in_file({ "line 3", "line 4", "line 5" }, file_lines)
    eq(result_overlap.found, false) -- Overlaps with both A and B
end

T["duplicate_handling"]["boundary_edge_cases"] = function()
    local file_lines = {
        "target", -- Line 1
        "other", -- Line 2
        "target", -- Line 3
    }

    -- Use single line block at line 1
    local result1 = _G.search_engine:locate_block_in_file({ "target" }, file_lines)
    eq(result1.found, true)
    eq(result1.start_line, 1)
    eq(result1.end_line, 1)

    -- Try to use a block that would start at line 1 (should be blocked)
    local result2 = _G.search_engine:locate_block_in_file({ "target", "other" }, file_lines)
    eq(result2.found, false) -- Line 1 is already used

    -- Single line at line 3 should still work
    local result3 = _G.search_engine:locate_block_in_file({ "target" }, file_lines)
    eq(result3.found, true)
    eq(result3.start_line, 3)
    eq(result3.end_line, 3)
end

T["duplicate_handling"]["prefer_exact_over_fuzzy_with_used_ranges"] = function()
    local search_lines = { "function test()" }
    local file_lines = {
        "function test()", -- Exact match
        "other content",
        "function test( )", -- Fuzzy match (extra space)
        "more content",
    }

    -- First search should prefer exact match
    local result1 = _G.search_engine:locate_block_in_file(search_lines, file_lines)
    eq(result1.found, true)
    eq(result1.start_line, 1)
    eq(result1.overall_match_type, _G.types.OVERALL_MATCH_TYPE.exact)

    -- Second search should fall back to fuzzy match
    local result2 = _G.search_engine:locate_block_in_file(search_lines, file_lines)
    eq(result2.found, true)
    eq(result2.start_line, 3)
    expect.equality(
        result2.overall_match_type == _G.types.OVERALL_MATCH_TYPE.exact_whitespace
            or result2.overall_match_type == _G.types.OVERALL_MATCH_TYPE.fuzzy_high,
        true
    )
end

T["duplicate_handling"]["multiple_identical_blocks"] = function()
    local search_lines = { "duplicate" }
    local file_lines = {}

    -- Create 7 lines with "duplicate" at positions 1, 3, 5, 7
    for i = 1, 7 do
        if i % 2 == 1 then
            table.insert(file_lines, "duplicate")
        else
            table.insert(file_lines, "other " .. i)
        end
    end

    local results = {}

    for i = 1, 4 do
        local result = _G.search_engine:locate_block_in_file(search_lines, file_lines)
        if result.found then
            table.insert(results, result.start_line)
        end
    end

    -- Should have found all 4 occurrences
    eq(#results, 4)

    expect.equality(results[1] == 1, true)
    expect.equality(results[2] == 3, true)
    expect.equality(results[3] == 5, true)
    expect.equality(results[4] == 7, true)
end

T["duplicate_handling"]["used_ranges_with_fuzzy_matching"] = function()
    local search_lines = { "function process(data)" }
    local file_lines = {
        "function process(data)", -- Exact match
        "other code",
        "function process( data )", -- Whitespace difference
        "more code",
        "function process(info)", -- Parameter difference
    }

    -- First search - should get exact match
    local result1 = _G.search_engine:locate_block_in_file(search_lines, file_lines)
    eq(result1.found, true)
    eq(result1.start_line, 1)
    eq(result1.overall_match_type, _G.types.OVERALL_MATCH_TYPE.exact)

    -- Second search - should get whitespace match
    local result2 = _G.search_engine:locate_block_in_file(search_lines, file_lines)
    eq(result2.found, true)
    eq(result2.start_line, 3)
    expect.equality(
        result2.overall_match_type == _G.types.OVERALL_MATCH_TYPE.exact_whitespace
            or result2.overall_match_type == _G.types.OVERALL_MATCH_TYPE.fuzzy_high,
        true
    )

    -- Third search - should get fuzzy match (if above threshold)
    local result3 = _G.search_engine:locate_block_in_file(search_lines, file_lines)
    if result3.found then
        eq(result3.start_line, 5)
        expect.equality(result3.overall_score < 1.0, true)
    else
        -- Acceptable if similarity is below threshold
        expect.equality(result3.error:match("No suitable match found") ~= nil, true)
    end
end

T["duplicate_handling"]["empty_used_ranges_initially"] = function()
    -- Test that a fresh search engine has no used ranges
    local fresh_engine = require("mcphub.native.neovim.files.edit_file.search_engine").new()

    local search_lines = { "test line" }
    local file_lines = { "test line", "other", "test line" }

    -- Should find first occurrence
    local result = fresh_engine:locate_block_in_file(search_lines, file_lines)
    eq(result.found, true)
    eq(result.start_line, 1)
end

T["duplicate_handling"]["position_availability_check"] = function()
    -- Test the internal _is_position_available logic indirectly
    local search_lines = { "target" }
    local file_lines = {
        "target", -- Will be used
        "other",
        "target", -- Should be available after first is used
        "content",
    }

    -- Use first position
    local result1 = _G.search_engine:locate_block_in_file(search_lines, file_lines)
    eq(result1.found, true)
    eq(result1.start_line, 1)

    -- Second search should skip used position and find available one
    local result2 = _G.search_engine:locate_block_in_file(search_lines, file_lines)
    eq(result2.found, true)
    eq(result2.start_line, 3) -- Should skip the used position at line 3
end

T["result_quality"] = new_set({
    hooks = {
        pre_case = function()
            -- Create search engine with early termination disabled for quality testing
            local SearchEngine = require("mcphub.native.neovim.files.edit_file.search_engine")
            _G.types = require("mcphub.native.neovim.files.edit_file.types")

            _G.search_engine = SearchEngine.new({
                early_termination_score = 1.1, -- Disabled (impossible score)
                fuzzy_threshold = 0.7,
                enable_fuzzy_matching = true,
            })
        end,
    },
})

T["result_quality"]["exact_beats_whitespace"] = function()
    local search_lines = { "function test()" }
    local file_lines = {
        "other content",
        "other content",
        "other content",
        "other content",
        "other content",
        "  function test()  ", -- Line 6 - Whitespace match
        "other content",
        "other content",
        "function test()", -- Line 9 - Exact match (found later)
        "more content",
    }

    local result = _G.search_engine:locate_block_in_file(search_lines, file_lines)

    eq(result.found, true)
    eq(result.start_line, 9) -- Should choose exact match despite being found later
    eq(result.overall_match_type, _G.types.OVERALL_MATCH_TYPE.exact)
    eq(result.overall_score, 1.0)
end

T["result_quality"]["whitespace_beats_fuzzy"] = function()
    local search_lines = { "function process(data)" }
    local file_lines = {
        "other content",
        "other content",
        "other content",
        "other content",
        "function process(info)", -- Line 5 - Fuzzy match (found first)
        "other content",
        "other content",
        "function process( data )", -- Line 8 - Whitespace match (found later)
        "more content",
    }

    _G.search_engine:reset_used_ranges()

    local result = _G.search_engine:locate_block_in_file(search_lines, file_lines)

    eq(result.found, true)
    eq(result.start_line, 8) -- Should choose whitespace match over fuzzy
    expect.equality(
        result.overall_match_type == _G.types.OVERALL_MATCH_TYPE.exact_whitespace
            or result.overall_match_type == _G.types.OVERALL_MATCH_TYPE.fuzzy_high,
        true
    )
    expect.equality(result.overall_score >= 0.95, true)
end

T["result_quality"]["high_fuzzy_beats_low_fuzzy"] = function()
    local search_lines = { "function calculateResult(input)" }
    local file_lines = {
        "other content",
        "other content",
        "other content",
        "function calculateOutput(param)", -- Line 4 - Lower similarity (found first)
        "other content",
        "other content",
        "function calculateResults(input)", -- Line 7 - Higher similarity (found later)
        "more content",
    }

    _G.search_engine:reset_used_ranges()

    local result = _G.search_engine:locate_block_in_file(search_lines, file_lines)

    eq(result.found, true)
    eq(result.start_line, 7) -- Should choose higher similarity match
    expect.equality(result.overall_match_type, _G.types.OVERALL_MATCH_TYPE.fuzzy_high)
    expect.equality(result.overall_score >= 0.85, true)
end

T["result_quality"]["score_based_tie_breaking"] = function()
    local search_lines = { "function test(param)" }
    local file_lines = {
        "other content",
        "other content",
        "function test(parameter)", -- Line 3 - Slight difference (found first)
        "other content",
        "other content",
        "other content",
        "function test(param2)", -- Line 7 - Different slight difference (found later)
        "more content",
    }

    _G.search_engine:reset_used_ranges()

    local result = _G.search_engine:locate_block_in_file(search_lines, file_lines)

    eq(result.found, true)
    -- Should choose whichever has higher similarity score
    expect.equality(result.start_line == 3 or result.start_line == 7, true)
    expect.equality(result.overall_score >= 0.70, true)
end

T["result_quality"]["match_type_priority_ordering"] = function()
    -- Test the complete priority chain - arrange so worse matches are found first
    local search_lines = { "target line" }
    local file_lines = {
        "other content",
        "other content",
        "target line fuzzy", -- Line 3 - Fuzzy low (found first)
        "other content",
        "TARGET LINE", -- Line 5 - Case difference (found second)
        "other content",
        " target line ", -- Line 7 - Whitespace (found third)
        "other content",
        "target line", -- Line 9 - Exact match (found last)
        "more content",
    }

    _G.search_engine:reset_used_ranges()

    local result = _G.search_engine:locate_block_in_file(search_lines, file_lines)

    eq(result.found, true)
    eq(result.start_line, 9) -- Should choose exact match despite being found last
    eq(result.overall_match_type, _G.types.OVERALL_MATCH_TYPE.exact)
end

T["result_quality"]["multiline_block_quality_comparison"] = function()
    local search_lines = { "function test()", "  return value", "end" }
    local file_lines = {
        "other content",
        "-- Block 1 (mixed quality) - found first",
        "function test()", -- Exact
        "return value", -- Whitespace diff
        "end", -- Exact
        "other content",
        "other content",
        "-- Block 2 (all exact) - found later",
        "function test()", -- Exact
        "  return value", -- Exact
        "end", -- Exact
        "-- End",
    }

    _G.search_engine:reset_used_ranges()

    local result = _G.search_engine:locate_block_in_file(search_lines, file_lines)

    eq(result.found, true)
    eq(result.start_line, 9) -- Should choose the all-exact block
    eq(result.end_line, 11)
    eq(result.overall_match_type, _G.types.OVERALL_MATCH_TYPE.exact)
    eq(result.overall_score, 1.0)
end

T["result_quality"]["quality_beats_position_preference"] = function()
    -- Higher quality match should win even if found much later
    local search_lines = { "function process(data)" }
    local file_lines = {
        "other content",
        "other content",
        "function process(info)", -- Line 3 - Fuzzy match (found early)
        "other content",
        "other content",
        "other content",
        "other content",
        "other content",
        "other content",
        "function process(data)", -- Line 10 - Exact match (found much later)
        "final content",
    }

    _G.search_engine:reset_used_ranges()

    local result = _G.search_engine:locate_block_in_file(search_lines, file_lines)

    eq(result.found, true)
    eq(result.start_line, 10) -- Should choose exact match despite much later position
    eq(result.overall_match_type, _G.types.OVERALL_MATCH_TYPE.exact)
end

T["result_quality"]["complex_quality_comparison"] = function()
    local search_lines = { "function calculate(a, b)", "  return a + b" }
    local file_lines = {
        "other content",
        "other content",
        "-- Option 1: One exact, one fuzzy - found first",
        "function calculate(a, b)", -- Exact
        "return a + b", -- Fuzzy (missing spaces)
        "other content",
        "-- Option 2: Both fuzzy but closer - found second",
        "function calculate(a,b)", -- Fuzzy (spacing)
        "  return a + b", -- Exact
        "other content",
        "other content",
        "-- Option 3: Both exact - found last",
        "function calculate(a, b)", -- Exact
        "  return a + b", -- Exact
        "-- End",
    }

    _G.search_engine:reset_used_ranges()

    local result = _G.search_engine:locate_block_in_file(search_lines, file_lines)

    eq(result.found, true)
    eq(result.start_line, 13) -- Should choose the all-exact option
    eq(result.end_line, 14)
    eq(result.overall_match_type, _G.types.OVERALL_MATCH_TYPE.exact)
end

T["result_quality"]["average_scoring_accuracy"] = function()
    local search_lines = { "line one", "line two", "line three" }
    local file_lines = {
        "other content",
        "line one", -- Exact (1.0)
        "  line two  ", -- Whitespace (0.99)
        "line three", -- Exact (1.0)
        "more content",
    }

    local result = _G.search_engine:locate_block_in_file(search_lines, file_lines)

    eq(result.found, true)
    eq(result.start_line, 2)
    eq(result.end_line, 4)

    -- Overall score should be average: (1.0 + 0.99 + 1.0) / 3 = 0.996...
    expect.equality(result.overall_score >= 0.99, true)
    expect.equality(result.overall_score < 1.0, true)
    eq(result.overall_match_type, _G.types.OVERALL_MATCH_TYPE.exact_whitespace)
end

return T
