-- Tests for String Utils - String normalization and comparison utilities
local new_set = MiniTest.new_set
local expect, eq = MiniTest.expect, MiniTest.expect.equality

local T = new_set({
    hooks = {
        pre_case = function()
            -- Load the string utils module for each test
            _G.string_utils = require("mcphub.native.neovim.files.edit_file.string_utils")
            _G.types = require("mcphub.native.neovim.files.edit_file.types")
        end,
        post_case = function()
            -- Clean up
            _G.string_utils = nil
            _G.types = nil
        end,
    },
})

-- Group 1: String Normalization
T["normalization"] = new_set()

T["normalization"]["typographic_characters"] = function()
    local input = "Text with… em-dash — and en-dash – plus non-breaking space"
    local expected = "Text with... em-dash - and en-dash - plus non-breaking space"

    local result = _G.string_utils.normalize_string(input, { typographic_chars = true })
    eq(result, expected)
end

T["normalization"]["html_entities"] = function()
    local input = "Code: &lt;div class=&quot;test&quot;&gt;&amp;nbsp;&lt;/div&gt;"
    local expected = 'Code: <div class="test">&nbsp;</div>'

    local result = _G.string_utils.normalize_string(input, { html_entities = true })
    eq(result, expected)
end

T["normalization"]["extra_whitespace_collapse"] = function()
    local input = "  Multiple   spaces    and\ttabs\n\n  "
    local expected = "Multiple spaces and tabs"

    local result = _G.string_utils.normalize_string(input, {
        extra_whitespace = true,
        trim = true,
    })
    eq(result, expected)
end

T["normalization"]["case_normalization"] = function()
    local input = "Mixed CaSe TeXt"
    local expected = "mixed case text"

    local result = _G.string_utils.normalize_string(input, { normalize_case = true })
    eq(result, expected)
end

T["normalization"]["comprehensive_normalization"] = function()
    local input = '  "Smart quotes" with… HTML &lt;tags&gt; and   extra spaces  '
    local expected = '"smart quotes" with... html <tags> and extra spaces'

    local result = _G.string_utils.normalize_string(input, {
        smart_quotes = true,
        typographic_chars = true,
        html_entities = true,
        extra_whitespace = true,
        trim = true,
        normalize_case = true,
    })
    eq(result, expected)
end

T["normalization"]["normalize_for_code"] = function()
    local input = '  function "test"() { return &lt;value&gt;; }  '
    local expected = 'function "test"() { return <value>; }'

    local result = _G.string_utils.normalize_for_code(input)
    eq(result, expected)

    -- Should preserve case for code
    expect.equality(result:match("function"), "function") -- not "FUNCTION"
end

T["normalization"]["normalize_aggressive"] = function()
    local input = '  FUNCTION "Test"() { RETURN &lt;VALUE&gt;; }  '
    local expected = 'function "test"() { return <value>; }'

    local result = _G.string_utils.normalize_aggressive(input)
    eq(result, expected)
end

T["normalization"]["normalize_punctuation"] = function()
    local input = "func( arg1 , arg2 ) { arr[ index ] ; }"
    local expected = "func(arg1, arg2){arr[index];}"

    local result = _G.string_utils.normalize_punctuation(input)
    eq(result, expected)
end

T["normalization"]["empty_and_nil_strings"] = function()
    eq(_G.string_utils.normalize_string(nil), "")
    eq(_G.string_utils.normalize_string(""), "")
    eq(_G.string_utils.normalize_string("   "), "")
end

-- Group 2: Levenshtein Distance and Similarity
T["similarity"] = new_set()

T["similarity"]["identical_strings"] = function()
    local str1 = "hello world"
    local str2 = "hello world"

    eq(_G.string_utils.levenshtein_distance(str1, str2), 0)
    eq(_G.string_utils.calculate_similarity(str1, str2), 1.0)
end

T["similarity"]["completely_different_strings"] = function()
    local str1 = "abc"
    local str2 = "xyz"

    eq(_G.string_utils.levenshtein_distance(str1, str2), 3)
    eq(_G.string_utils.calculate_similarity(str1, str2), 0.0)
end

T["similarity"]["single_character_difference"] = function()
    local str1 = "hello"
    local str2 = "hallo"

    eq(_G.string_utils.levenshtein_distance(str1, str2), 1)
    -- Similarity should be 4/5 = 0.8
    expect.equality(math.abs(_G.string_utils.calculate_similarity(str1, str2) - 0.8) < 0.01, true)
end

T["similarity"]["insertion_and_deletion"] = function()
    local str1 = "test"
    local str2 = "testing"

    eq(_G.string_utils.levenshtein_distance(str1, str2), 3) -- 3 insertions

    local str3 = "testing"
    local str4 = "test"
    eq(_G.string_utils.levenshtein_distance(str3, str4), 3) -- 3 deletions
end

T["similarity"]["empty_string_cases"] = function()
    eq(_G.string_utils.levenshtein_distance("", ""), 0)
    eq(_G.string_utils.levenshtein_distance("", "abc"), 3)
    eq(_G.string_utils.levenshtein_distance("abc", ""), 3)

    eq(_G.string_utils.calculate_similarity("", ""), 1.0)
    eq(_G.string_utils.calculate_similarity("", "abc"), 0.0)
    eq(_G.string_utils.calculate_similarity("abc", ""), 0.0)
end

T["similarity"]["long_strings"] = function()
    local str1 = "The quick brown fox jumps over the lazy dog"
    local str2 = "The quick brown fox jumps over the lazy cat"

    -- Only "dog" -> "cat" difference
    eq(_G.string_utils.levenshtein_distance(str1, str2), 3)

    -- Should have high similarity
    local similarity = _G.string_utils.calculate_similarity(str1, str2)
    expect.equality(similarity > 0.9, true)
end

-- Group 3: Line Comparison
T["line_comparison"] = new_set()

T["line_comparison"]["exact_match"] = function()
    local line1 = "local x = 1"
    local line2 = "local x = 1"

    local match_type, score, differences = _G.string_utils.compare_lines(line1, line2)

    eq(match_type, _G.types.LINE_MATCH_TYPE.exact)
    eq(score, 1.0)
    eq(vim.deep_equal(differences, {}), true)
end

T["line_comparison"]["whitespace_only_difference"] = function()
    local line1 = "  local   x =  1  "
    local line2 = "local x = 1"

    local match_type, score, differences = _G.string_utils.compare_lines(line1, line2)

    eq(match_type, _G.types.LINE_MATCH_TYPE.exact_whitespace)
    eq(score, 0.99)
    expect.equality(vim.tbl_contains(differences, _G.types.DIFFERENCE_TYPE.whitespace), true)
end

T["line_comparison"]["punctuation_difference"] = function()
    local line1 = "func(arg1,arg2);"
    local line2 = "func(arg1, arg2)"

    local match_type, score = _G.string_utils.compare_lines(line1, line2)

    eq(match_type, _G.types.LINE_MATCH_TYPE.punctuation)
    eq(score, 0.95)
end

T["line_comparison"]["case_difference"] = function()
    local line1 = "FUNCTION testFunction()"
    local line2 = "function testfunction()"

    local match_type, score, differences = _G.string_utils.compare_lines(line1, line2)

    eq(match_type, _G.types.LINE_MATCH_TYPE.case_insensitive)
    eq(score, 0.90)
    expect.equality(vim.tbl_contains(differences, _G.types.DIFFERENCE_TYPE.case), true)
end

T["line_comparison"]["high_fuzzy_match"] = function()
    local line1 = "function calculate_result(input)"
    local line2 = "function calculate_results(input)"
    -- Only one character difference

    local match_type, score = _G.string_utils.compare_lines(line1, line2)

    eq(match_type, _G.types.LINE_MATCH_TYPE.fuzzy_high)
    expect.equality(score >= 0.85, true)
end

T["line_comparison"]["medium_fuzzy_match"] = function()
    local line1 = "function process_data(input)"
    local line2 = "function process_data(param)"

    local match_type, score = _G.string_utils.compare_lines(line1, line2)

    expect.equality(
        match_type == _G.types.LINE_MATCH_TYPE.fuzzy_medium or match_type == _G.types.LINE_MATCH_TYPE.fuzzy_high,
        true
    )
    expect.equality(score > 0.7, true)
end

T["line_comparison"]["low_fuzzy_match"] = function()
    local line1 = "function process_data(input)"
    local line2 = "let result = calculate(x, y)"

    local match_type, score = _G.string_utils.compare_lines(line1, line2)

    expect.equality(
        match_type == _G.types.LINE_MATCH_TYPE.fuzzy_low or match_type == _G.types.LINE_MATCH_TYPE.no_match,
        true
    )
    expect.equality(score < 0.85, true)
end

T["line_comparison"]["no_match"] = function()
    local line1 = "completely different content here"
    local line2 = "xyz abc 123 totally unrelated"

    local match_type, score = _G.string_utils.compare_lines(line1, line2)

    eq(match_type, _G.types.LINE_MATCH_TYPE.no_match)
    expect.equality(score < 0.50, true)
end

-- Group 4: Difference Detection
T["difference_detection"] = new_set()

T["difference_detection"]["quote_style_differences"] = function()
    local line1 = 'print("hello")'
    local line2 = "print('hello')"

    local differences = _G.string_utils._detect_differences(line1, line2)
    expect.equality(vim.tbl_contains(differences, _G.types.DIFFERENCE_TYPE.quote_style), true)
end

T["difference_detection"]["html_entity_differences"] = function()
    local line1 = "value &lt; threshold"
    local line2 = "value < threshold"

    local differences = _G.string_utils._detect_differences(line1, line2)
    expect.equality(vim.tbl_contains(differences, _G.types.DIFFERENCE_TYPE.html_entities), true)
end

T["difference_detection"]["case_differences"] = function()
    local line1 = "Function Name"
    local line2 = "function name"

    local differences = _G.string_utils._detect_differences(line1, line2)
    expect.equality(vim.tbl_contains(differences, _G.types.DIFFERENCE_TYPE.case), true)
end

T["difference_detection"]["whitespace_differences"] = function()
    local line1 = "  spaced   content  "
    local line2 = "spaced content"

    local differences = _G.string_utils._detect_differences(line1, line2)
    expect.equality(vim.tbl_contains(differences, _G.types.DIFFERENCE_TYPE.whitespace), true)
end

-- Group 5: Edge Cases and Error Handling
T["edge_cases"] = new_set()

T["edge_cases"]["unicode_handling"] = function()
    local line1 = "🚀 Rocket emoji test 🎉"
    local line2 = "🚀 Rocket emoji test 🎊"

    local match_type, score = _G.string_utils.compare_lines(line1, line2)

    -- Should handle unicode without crashing
    eq(type(match_type), "string")
    eq(type(score), "number")
    expect.equality(score > 0.8, true) -- Should be high similarity
end

T["edge_cases"]["very_long_lines"] = function()
    local long_content = string.rep("very long content ", 100)
    local line1 = "prefix " .. long_content .. " suffix"
    local line2 = "prefix " .. long_content .. " different_suffix"

    local match_type, score = _G.string_utils.compare_lines(line1, line2)

    -- Should handle long lines without performance issues
    eq(type(match_type), "string")
    eq(type(score), "number")
    expect.equality(score > 0.9, true) -- Should be high similarity due to mostly same content
end

T["edge_cases"]["empty_lines"] = function()
    local match_type, score = _G.string_utils.compare_lines("", "")
    eq(match_type, _G.types.LINE_MATCH_TYPE.exact)
    eq(score, 1.0)

    local match_type2, score2 = _G.string_utils.compare_lines("", "content")
    eq(match_type2, _G.types.LINE_MATCH_TYPE.no_match)
    eq(score2, 0.0)
end

T["edge_cases"]["special_regex_characters"] = function()
    local line1 = "regex: ^.*[a-z]+$.test(input)"
    local line2 = "regex: ^.*[a-z]+$.test(input)"

    local match_type, score = _G.string_utils.compare_lines(line1, line2)

    eq(match_type, _G.types.LINE_MATCH_TYPE.exact)
    eq(score, 1.0)
end

T["edge_cases"]["normalization_stress_test"] = function()
    local complex_input = '  "Smart"… &lt;HTML&gt; \t\n   Mixed   CASE   '

    -- Should not crash on complex input
    local result = _G.string_utils.normalize_aggressive(complex_input)
    eq(type(result), "string")

    -- Should produce clean output
    expect.equality(result:match("smart"), "smart")
    expect.equality(result:match("<html>"), "<html>")
    expect.equality(result:match("mixed"), "mixed")
end

return T
