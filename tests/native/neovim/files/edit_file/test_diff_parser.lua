-- Tests for DiffParser - Basic Parsing functionality
local new_set = MiniTest.new_set
local expect, eq = MiniTest.expect, MiniTest.expect.equality

local T = new_set({
    hooks = {
        pre_case = function()
            -- Create a fresh DiffParser instance for each test
            local DiffParser = require("mcphub.native.neovim.files.edit_file.diff_parser")
            _G.test_parser = DiffParser.new()
        end,
        post_case = function()
            -- Clean up
            _G.test_parser = nil
        end,
    },
})

-- Test setup
T["basic_parsing"] = new_set()

T["basic_parsing"]["single_valid_block"] = function()
    local diff_content = [[<<<<<<< SEARCH
local x = 1
=======
local x = 2
>>>>>>> REPLACE]]

    local blocks, error = _G.test_parser:parse(diff_content)

    -- Should parse successfully
    eq(error, nil)
    eq(type(blocks), "table")
    eq(#blocks, 1)

    -- Check block structure
    local block = blocks[1]
    eq(block.search_content, "local x = 1")
    eq(block.replace_content, "local x = 2")
    eq(block.block_id, "Block 1")
    eq(vim.deep_equal(block.search_lines, { "local x = 1" }), true)
    eq(vim.deep_equal(block.replace_lines, { "local x = 2" }), true)
end

T["basic_parsing"]["multiple_consecutive_blocks"] = function()
    local diff_content = [[<<<<<<< SEARCH
function foo()
    return 1
end
=======
function foo()
    return 2
end
>>>>>>> REPLACE

<<<<<<< SEARCH
local bar = "hello"
=======
local bar = "world"
>>>>>>> REPLACE]]

    local blocks, error = _G.test_parser:parse(diff_content)

    -- Should parse successfully
    eq(error, nil)
    eq(type(blocks), "table")
    eq(#blocks, 2)

    -- Check first block
    local block1 = blocks[1]
    eq(
        block1.search_content,
        [[function foo()
    return 1
end]]
    )
    eq(
        block1.replace_content,
        [[function foo()
    return 2
end]]
    )
    eq(block1.block_id, "Block 1")

    -- Check second block
    local block2 = blocks[2]
    eq(block2.search_content, [[local bar = "hello"]])
    eq(block2.replace_content, [[local bar = "world"]])
    eq(block2.block_id, "Block 2")
end

T["basic_parsing"]["deletion_block_empty_replace"] = function()
    local diff_content = [[<<<<<<< SEARCH
-- This comment should be deleted
local unused_var = 123
=======
>>>>>>> REPLACE]]

    local blocks, error = _G.test_parser:parse(diff_content)

    -- Should parse successfully
    eq(error, nil)
    eq(#blocks, 1)

    local block = blocks[1]
    eq(
        block.search_content,
        [[-- This comment should be deleted
local unused_var = 123]]
    )
    eq(block.replace_content, "")
    eq(vim.deep_equal(block.replace_lines, {}), true)
end

T["basic_parsing"]["addition_block_empty_search"] = function()
    local diff_content = [[<<<<<<< SEARCH
=======
-- New comment added
local new_var = 456
>>>>>>> REPLACE]]

    local blocks, error = _G.test_parser:parse(diff_content)

    -- Should parse successfully
    eq(error, nil)
    eq(#blocks, 1)

    local block = blocks[1]
    eq(block.search_content, "")
    eq(
        block.replace_content,
        [[-- New comment added
local new_var = 456]]
    )
    eq(vim.deep_equal(block.search_lines, {}), true)
end

T["basic_parsing"]["content_with_special_characters"] = function()
    local diff_content = [[<<<<<<< SEARCH
local str = "Hello \"world\""
local regex = "\d+\.\d+"
local unicode = "🚀 emoji test"
=======
local str = 'Hello "world"'
local regex = "\d+\.\d+"
local unicode = "🎉 different emoji"
>>>>>>> REPLACE]]

    local blocks, error = _G.test_parser:parse(diff_content)

    -- Should parse successfully
    eq(error, nil)
    eq(#blocks, 1)

    local block = blocks[1]
    eq(
        block.search_content,
        [[local str = "Hello \"world\""
local regex = "\d+\.\d+"
local unicode = "🚀 emoji test"]]
    )
    eq(
        block.replace_content,
        [[local str = 'Hello "world"'
local regex = "\d+\.\d+"
local unicode = "🎉 different emoji"]]
    )
end

T["basic_parsing"]["no_issues_for_valid_input"] = function()
    local diff_content = [[<<<<<<< SEARCH
valid content
=======
replaced content
>>>>>>> REPLACE]]

    local blocks, error = _G.test_parser:parse(diff_content)

    -- Should parse successfully with no issues
    eq(error, nil)
    eq(_G.test_parser:has_issues(), false)
    eq(_G.test_parser:get_feedback(), nil)
end

T["basic_parsing"]["nested_search_markers"] = function()
    local diff_content = [[<<<<<<< SEARCH
local x = 1
\<<<<<<< SEARCH
local y = 2
=======
local y = 3
>>>>>>> REPLACE]]

    local blocks, error = _G.test_parser:parse(diff_content)

    eq(error, nil)
    eq(#blocks, 1)
    local block = blocks[1]
    eq(block.search_lines[2], "<<<<<<<< SEARCH")
end

-- Group 2: Malformed Input and Issue Tracking
T["malformed_input"] = new_set()

T["malformed_input"]["extra_spaces_in_markers"] = function()
    local diff_content = [[<<<<<<<  SEARCH
local x = 1
=======
local x = 2
>>>>>>>  REPLACE]]

    local blocks, error = _G.test_parser:parse(diff_content)

    -- Should parse successfully despite extra spaces
    eq(error, nil)
    eq(#blocks, 1)

    local block = blocks[1]
    eq(block.search_content, "local x = 1")
    eq(block.replace_content, "local x = 2")

    -- Should track the spacing issue
    eq(_G.test_parser:has_issues(), true)
    local feedback = _G.test_parser:get_feedback()
    eq(type(feedback), "string")
    expect.equality(feedback:match("Extra spaces found in search/replace markers") ~= nil, true)
end

T["malformed_input"]["missing_spaces_in_markers"] = function()
    local diff_content = [[<<<<<<<SEARCH
local x = 1
=======
local x = 2
>>>>>>>REPLACE]]

    local blocks, error = _G.test_parser:parse(diff_content)

    -- Should parse successfully despite missing spaces
    eq(error, nil)
    eq(#blocks, 1)

    local block = blocks[1]
    eq(block.search_content, "local x = 1")
    eq(block.replace_content, "local x = 2")

    -- Should track the spacing issue
    eq(_G.test_parser:has_issues(), true)
    local feedback = _G.test_parser:get_feedback()
    eq(type(feedback), "string")
    expect.equality(feedback:match("No space between markers and keywords") ~= nil, true)
end

T["malformed_input"]["case_mismatch_markers"] = function()
    local diff_content = [[<<<<<<< search
local x = 1
=======
local x = 2
>>>>>>> replace]]

    local blocks, error = _G.test_parser:parse(diff_content)

    -- Should parse successfully despite case mismatch
    eq(error, nil)
    eq(#blocks, 1)

    local block = blocks[1]
    eq(block.search_content, "local x = 1")
    eq(block.replace_content, "local x = 2")

    -- Should track the case issue
    eq(_G.test_parser:has_issues(), true)
    local feedback = _G.test_parser:get_feedback()
    eq(type(feedback), "string")
    expect.equality(feedback:match("Inconsistent case in SEARCH/REPLACE keywords") ~= nil, true)
end

T["malformed_input"]["content_on_search_marker_line"] = function()
    local diff_content = [[<<<<<<< SEARCH local x = 1
=======
local x = 2
>>>>>>> REPLACE]]

    local blocks, error = _G.test_parser:parse(diff_content)

    -- Should parse successfully and extract inline content
    eq(error, nil)
    eq(#blocks, 1)

    local block = blocks[1]
    eq(block.search_content, "local x = 1")
    eq(block.replace_content, "local x = 2")

    -- -- Should track the inline content issue
    eq(_G.test_parser:has_issues(), true)
    local feedback = _G.test_parser:get_feedback()
    eq(type(feedback), "string")
    expect.equality(feedback:match("marker line contains content") ~= nil, true)
end

T["malformed_input"]["claude_style_inline_content"] = function()
    -- Claude sometimes puts content after the search marker with a ">" separator
    local diff_content = [[<<<<<<< SEARCH> local x = 1
=======
local x = 2
>>>>>>> REPLACE]]

    local blocks, error = _G.test_parser:parse(diff_content)

    -- Should parse successfully and extract Claude-style content
    eq(error, nil)
    eq(#blocks, 1)

    local block = blocks[1]
    eq(block.search_content, "local x = 1")
    eq(block.replace_content, "local x = 2")

    -- Should track the inline content issue
    eq(_G.test_parser:has_issues(), true)
    local feedback = _G.test_parser:get_feedback()
    eq(type(feedback), "string")
    expect.equality(feedback:match("marker line is not EXACT") ~= nil, true)
end

T["malformed_input"]["missing_search_marker"] = function()
    local diff_content = [[local x = 1
=======
local x = 2
>>>>>>> REPLACE]]

    local blocks, error = _G.test_parser:parse(diff_content)

    -- Should parse successfully by auto-adding missing marker
    eq(error, nil)
    eq(#blocks, 1)

    local block = blocks[1]
    eq(block.search_content, "local x = 1")
    eq(block.replace_content, "local x = 2")

    -- Should track the missing marker issue
    eq(_G.test_parser:has_issues(), true)
    local feedback = _G.test_parser:get_feedback()
    eq(type(feedback), "string")
    expect.equality(feedback:match("Missing or malformed SEARCH marker") ~= nil, true)
end

T["malformed_input"]["multiple_issues_combined"] = function()
    local diff_content = [[<<<<<<<  search content here
=======
local x = 2
>>>>>>>replace]]

    local blocks, error = _G.test_parser:parse(diff_content)

    -- Should parse successfully despite multiple issues
    eq(error, nil)
    eq(#blocks, 1)

    local block = blocks[1]
    eq(block.search_content, "content here")
    eq(block.replace_content, "local x = 2")

    -- Should track multiple issues
    eq(_G.test_parser:has_issues(), true)
    local feedback = _G.test_parser:get_feedback()
    eq(type(feedback), "string")

    -- Should mention multiple types of issues
    expect.equality(feedback:match("marker line contains content") ~= nil, true)
    expect.equality(feedback:match("Inconsistent case") ~= nil, true)
    expect.equality(feedback:match("No space between markers and keywords") ~= nil, true)
    expect.equality(feedback:match("Extra spaces found") ~= nil, true)
end

T["malformed_input"]["issue_count_tracking"] = function()
    local diff_content = [[<<<<<<<  SEARCH extra content
=======
local x = 2
>>>>>>>  REPLACE]]

    local blocks, error = _G.test_parser:parse(diff_content)

    eq(error, nil)
    eq(_G.test_parser:has_issues(), true)
end

-- Group 3: Invalid Structures and Error Handling
T["invalid_structures"] = new_set()

T["invalid_structures"]["missing_separator"] = function()
    local diff_content = [[<<<<<<< SEARCH
local x = 1
local y = 2
>>>>>>> REPLACE]]

    local blocks, error = _G.test_parser:parse(diff_content)

    -- Should fail to parse due to missing separator
    eq(blocks, nil)
    eq(type(error), "string")
    expect.equality(error:match("REPLACE marker must follow a SEARCH marker and a SEPARATOR.") ~= nil, true)
end

T["invalid_structures"]["missing_replace_marker"] = function()
    local diff_content = [[<<<<<<< SEARCH
local x = 1
=======
local x = 2]]

    local blocks, error = _G.test_parser:parse(diff_content)

    -- Should fail to parse due to missing replace marker
    eq(blocks, nil)
    eq(type(error), "string")
    expect.equality(error:match("missing replace marker") ~= nil, true)
end

T["invalid_structures"]["unexpected_separator_order"] = function()
    local diff_content = [[=======
local x = 1
<<<<<<< SEARCH
local x = 2
>>>>>>> REPLACE]]

    local blocks, error = _G.test_parser:parse(diff_content)

    -- Should fail due to separator appearing before search marker
    eq(blocks, nil)
    eq(type(error), "string")
end

T["invalid_structures"]["multiple_separators"] = function()
    local diff_content = [[<<<<<<< SEARCH
local x = 1
=======
local x = 2
=======
local x = 3
>>>>>>> REPLACE]]

    local blocks, error = _G.test_parser:parse(diff_content)

    -- Should fail due to multiple separators in one block
    eq(blocks, nil)
    eq(type(error), "string")
    expect.equality(error:match("Unexpected") ~= nil, true)
end

T["invalid_structures"]["incomplete_search_block"] = function()
    local diff_content = [[<<<<<<< SEARCH
local x = 1
local y = 2]]

    local blocks, error = _G.test_parser:parse(diff_content)

    -- Should fail due to incomplete block
    eq(blocks, nil)
    eq(type(error), "string")
    expect.equality(error:match("Incomplete") ~= nil or error:match("missing") ~= nil, true)
end

T["invalid_structures"]["incomplete_replace_block"] = function()
    local diff_content = [[<<<<<<< SEARCH
local x = 1
=======
local x = 2
local y = 3]]

    local blocks, error = _G.test_parser:parse(diff_content)

    -- Should fail due to incomplete replace section
    eq(blocks, nil)
    eq(type(error), "string")
    expect.equality(error:match("Incomplete") ~= nil or error:match("missing") ~= nil, true)
end

T["invalid_structures"]["empty_diff_content"] = function()
    local diff_content = ""

    local blocks, error = _G.test_parser:parse(diff_content)

    -- Should fail due to empty content
    eq(blocks, nil)
    eq(type(error), "string")
    expect.equality(error:match("Empty") ~= nil, true)
end

T["invalid_structures"]["mixed_valid_and_invalid_blocks"] = function()
    local diff_content = [[<<<<<<< SEARCH
local x = 1
=======
local x = 2
>>>>>>> REPLACE

<<<<<<< SEARCH
local y = 1
-- Missing separator and replace marker]]

    local blocks, error = _G.test_parser:parse(diff_content)

    -- Should fail due to the invalid second block
    eq(blocks, nil)
    eq(type(error), "string")
    expect.equality(error:match("Incomplete") ~= nil or error:match("missing") ~= nil, true)
end

T["invalid_structures"]["marker_content_with_escape_sequences"] = function()
    -- Test content that contains escaped marker-like sequences
    local diff_content = [[<<<<<<< SEARCH
\<<<<<<< not a marker"
\======= also not a separator")
=======
local str = "\\>>>>>>> not a replace marker"
print("Normal content")
>>>>>>> REPLACE]]

    local blocks, error = _G.test_parser:parse(diff_content)

    -- Should parse successfully since these are escaped
    eq(error, nil)
    eq(#blocks, 1)

    local block = blocks[1]
    expect.equality(block.search_content:match("not a marker") ~= nil, true)
    expect.equality(block.replace_content:match("not a replace marker") ~= nil, true)
end

return T
