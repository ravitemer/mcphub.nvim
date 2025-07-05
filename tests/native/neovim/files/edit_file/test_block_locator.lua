-- Tests for BlockLocator - Parser-to-Search Integration
local new_set = MiniTest.new_set
local expect, eq = MiniTest.expect, MiniTest.expect.equality

local T = new_set({
    hooks = {
        pre_case = function()
            -- Load required modules for each test
            local BlockLocator = require("mcphub.native.neovim.files.edit_file.block_locator")
            local DiffParser = require("mcphub.native.neovim.files.edit_file.diff_parser")
            _G.types = require("mcphub.native.neovim.files.edit_file.types")

            -- Create fresh instances
            _G.block_locator = BlockLocator.new()
            _G.diff_parser = DiffParser.new()
        end,
        post_case = function()
            -- Clean up
            _G.block_locator = nil
            _G.diff_parser = nil
            _G.types = nil
        end,
    },
})

-- Group 1: Parser-to-Search Integration
T["parser_search_integration"] = new_set()

T["parser_search_integration"]["single_block_successful_location"] = function()
    -- Test complete workflow: parse → locate
    local diff_content = [[<<<<<<< SEARCH
function test()
    return true
end
=======
function test()
    return false
end
>>>>>>> REPLACE]]

    local file_content = [[-- Header comment
function test()
    return true
end
-- Footer comment]]

    -- Parse the diff
    local parsed_blocks, parse_error = _G.diff_parser:parse(diff_content)
    eq(parse_error, nil)
    eq(#parsed_blocks, 1)

    -- Locate the blocks
    local located_blocks = _G.block_locator:locate_all_blocks(parsed_blocks, file_content)
    eq(#located_blocks, 1)

    local located_block = located_blocks[1]

    -- Check that parser data is preserved
    eq(located_block.search_content, parsed_blocks[1].search_content)
    eq(located_block.replace_content, parsed_blocks[1].replace_content)
    eq(located_block.block_id, parsed_blocks[1].block_id)
    eq(vim.deep_equal(located_block.search_lines, parsed_blocks[1].search_lines), true)
    eq(vim.deep_equal(located_block.replace_lines, parsed_blocks[1].replace_lines), true)

    -- Check that location was successful
    eq(located_block.location_result.found, true)
    eq(located_block.location_result.start_line, 2)
    eq(located_block.location_result.end_line, 4)
    eq(located_block.location_result.overall_match_type, _G.types.OVERALL_MATCH_TYPE.exact)
end

T["parser_search_integration"]["multiple_blocks_sequential_processing"] = function()
    local diff_content = [[<<<<<<< SEARCH
function first()
=======
function first_updated()
>>>>>>> REPLACE

<<<<<<< SEARCH
function second()
=======
function second_updated()
>>>>>>> REPLACE]]

    local file_content = [[function first()
    return 1
end

function second()
    return 2
end]]

    local parsed_blocks, parse_error = _G.diff_parser:parse(diff_content)
    eq(parse_error, nil)
    eq(#parsed_blocks, 2)

    local located_blocks = _G.block_locator:locate_all_blocks(parsed_blocks, file_content)
    eq(#located_blocks, 2)

    -- Check that both blocks are processed and located
    for i = 1, 2 do
        local located_block = located_blocks[i]
        local parsed_block = parsed_blocks[i]

        -- Verify parser data preservation
        eq(located_block.search_content, parsed_block.search_content)
        eq(located_block.replace_content, parsed_block.replace_content)
        eq(located_block.block_id, parsed_block.block_id)

        -- Verify successful location
        eq(located_block.location_result.found, true)
    end

    -- Check that blocks don't overlap (used ranges working)
    local block1 = located_blocks[1]
    local block2 = located_blocks[2]
    eq(block1.location_result.start_line, 1)
    eq(block2.location_result.start_line, 5) -- Should be after first block
end

T["parser_search_integration"]["block_metadata_preservation"] = function()
    local diff_content = [[<<<<<<< SEARCH
original content
=======
new content
>>>>>>> REPLACE]]

    local file_content = [[original content
other stuff]]

    local parsed_blocks, parse_error = _G.diff_parser:parse(diff_content)
    eq(parse_error, nil)

    local located_blocks = _G.block_locator:locate_all_blocks(parsed_blocks, file_content)
    eq(#located_blocks, 1)

    local parsed_block = parsed_blocks[1]
    local located_block = located_blocks[1]

    -- Verify all metadata fields are preserved
    eq(located_block.search_content, parsed_block.search_content)
    eq(located_block.replace_content, parsed_block.replace_content)
    eq(located_block.block_id, parsed_block.block_id)

    -- Check line arrays are deep-copied correctly
    eq(vim.deep_equal(located_block.search_lines, parsed_block.search_lines), true)
    eq(vim.deep_equal(located_block.replace_lines, parsed_block.replace_lines), true)
end

T["parser_search_integration"]["search_engine_result_transformation"] = function()
    local diff_content = [[<<<<<<< SEARCH
function fuzzy_match()
=======
function fuzzy_match_updated()
>>>>>>> REPLACE]]

    local file_content = [[function fuzzy_match( )
    return value
end]]

    local parsed_blocks = _G.diff_parser:parse(diff_content)
    local located_blocks = _G.block_locator:locate_all_blocks(parsed_blocks, file_content)

    local located_block = located_blocks[1]
    local location_result = located_block.location_result

    -- Verify search engine results are properly transformed
    eq(location_result.found, true)
    eq(type(location_result.start_line), "number")
    eq(type(location_result.end_line), "number")
    eq(type(location_result.overall_score), "number")
    eq(type(location_result.overall_match_type), "string")
    eq(type(location_result.confidence), "number")

    -- Verify line details are preserved
    eq(type(location_result.line_details), "table")
    expect.equality(#location_result.line_details > 0, true)
end

T["parser_search_integration"]["failed_location_handling"] = function()
    local diff_content = [[<<<<<<< SEARCH
nonexistent function()
    return impossible
=======
replacement content
>>>>>>> REPLACE]]

    local file_content = [[function real_function()
    return actual_value
end]]

    local parsed_blocks = _G.diff_parser:parse(diff_content)
    local located_blocks = _G.block_locator:locate_all_blocks(parsed_blocks, file_content)

    eq(#located_blocks, 1)
    local located_block = located_blocks[1]

    -- Parser data should still be preserved
    eq(located_block.search_content, parsed_blocks[1].search_content)
    eq(located_block.replace_content, parsed_blocks[1].replace_content)
    eq(located_block.block_id, parsed_blocks[1].block_id)

    -- Location should have failed
    eq(located_block.location_result.found, false)
    eq(type(located_block.location_result.error), "string")
    expect.equality(located_block.location_result.error:match("No suitable match found") ~= nil, true)
end

T["parser_search_integration"]["mixed_success_failure_blocks"] = function()
    local diff_content = [[<<<<<<< SEARCH
function exists()
=======
function exists_updated()
>>>>>>> REPLACE

<<<<<<< SEARCH
function does_not_exist()
=======
function replacement()
>>>>>>> REPLACE

<<<<<<< SEARCH
function also_exists()
=======
function also_exists_updated()
>>>>>>> REPLACE]]

    local file_content = [[function exists()
    return 1
end

function also_exists()
    return 2
end]]

    local parsed_blocks = _G.diff_parser:parse(diff_content)
    local located_blocks = _G.block_locator:locate_all_blocks(parsed_blocks, file_content)

    eq(#located_blocks, 3)

    -- First block: should succeed
    eq(located_blocks[1].location_result.found, true)
    eq(located_blocks[1].location_result.start_line, 1)

    -- Second block: should fail
    eq(located_blocks[2].location_result.found, false)
    eq(type(located_blocks[2].location_result.error), "string")

    -- Third block: should succeed
    eq(located_blocks[3].location_result.found, true)
    eq(located_blocks[3].location_result.start_line, 5)

    -- All blocks should preserve their original parsed data
    for i = 1, 3 do
        eq(located_blocks[i].search_content, parsed_blocks[i].search_content)
        eq(located_blocks[i].replace_content, parsed_blocks[i].replace_content)
        eq(located_blocks[i].block_id, parsed_blocks[i].block_id)
    end
end

T["parser_search_integration"]["fuzzy_matching_integration"] = function()
    local diff_content = [[<<<<<<< SEARCH
function calculateValue(input)
=======
function calculateValue(data)
>>>>>>> REPLACE]]

    local file_content = [[function calculateValues(input)
    return process(input)
end]]

    local parsed_blocks = _G.diff_parser:parse(diff_content)
    local located_blocks = _G.block_locator:locate_all_blocks(parsed_blocks, file_content)

    eq(#located_blocks, 1)
    local located_block = located_blocks[1]

    -- Should find via fuzzy matching
    eq(located_block.location_result.found, true)
    expect.equality(located_block.location_result.overall_match_type ~= _G.types.OVERALL_MATCH_TYPE.exact, true)
    expect.equality(located_block.location_result.overall_score < 1.0, true)
    expect.equality(located_block.location_result.overall_score >= 0.8, true)

    -- Line details should show the fuzzy match information
    expect.equality(#located_block.location_result.line_details > 0, true)
    local line_detail = located_block.location_result.line_details[1]
    expect.equality(line_detail.line_match_type ~= _G.types.LINE_MATCH_TYPE.exact, true)
end

T["parser_search_integration"]["search_engine_configuration_respected"] = function()
    -- Test with custom configuration
    local custom_locator = require("mcphub.native.neovim.files.edit_file.block_locator").new({
        fuzzy_threshold = 0.95, -- Very high threshold
        enable_fuzzy_matching = true,
    })

    local diff_content = [[<<<<<<< SEARCH
function similarFunction()
=======
function similarFunction_updated()
>>>>>>> REPLACE]]

    local file_content = [[function differentFunction()
    return value
end]]

    local parsed_blocks = _G.diff_parser:parse(diff_content)
    local located_blocks = custom_locator:locate_all_blocks(parsed_blocks, file_content)

    eq(#located_blocks, 1)
    local located_block = located_blocks[1]

    -- Should fail due to high fuzzy threshold
    eq(located_block.location_result.found, false)
    expect.equality(located_block.location_result.error:match("No suitable match found") ~= nil, true)
end

T["parser_search_integration"]["multiline_block_coordination"] = function()
    local diff_content = [[<<<<<<< SEARCH
function complex_function() {
    if (condition) {
        return result;
    }
}
=======
function complex_function() {
    if (new_condition) {
        return new_result;
    }
}
>>>>>>> REPLACE]]

    local file_content = [[class MyClass {
    function complex_function() {
        if (condition) {
            return result;
        }
    }
    
    function other_method() {
        return other;
    }
}]]

    local parsed_blocks = _G.diff_parser:parse(diff_content)
    local located_blocks = _G.block_locator:locate_all_blocks(parsed_blocks, file_content)

    eq(#located_blocks, 1)
    local located_block = located_blocks[1]

    eq(located_block.location_result.found, true)
    eq(located_block.location_result.start_line, 2)
    eq(located_block.location_result.end_line, 6)

    -- Verify multiline content is preserved correctly
    expect.equality(#located_block.search_lines, 5)
    expect.equality(#located_block.replace_lines, 5)
    eq(located_block.search_lines[1], "function complex_function() {")
    eq(located_block.search_lines[5], "}")
end

T["parser_search_integration"]["empty_file_handling"] = function()
    local diff_content = [[<<<<<<< SEARCH
some content
=======
replacement content
>>>>>>> REPLACE]]

    local file_content = "" -- Empty file

    local parsed_blocks = _G.diff_parser:parse(diff_content)
    local located_blocks = _G.block_locator:locate_all_blocks(parsed_blocks, file_content)

    eq(#located_blocks, 1)
    local located_block = located_blocks[1]

    -- Should fail to locate in empty file
    eq(located_block.location_result.found, false)
    eq(type(located_block.location_result.error), "string")
end

T["parser_search_integration"]["location_result_completeness"] = function()
    local diff_content = [[<<<<<<< SEARCH
target content
=======
new content
>>>>>>> REPLACE]]

    local file_content = [[target content
other stuff]]

    local parsed_blocks = _G.diff_parser:parse(diff_content)
    local located_blocks = _G.block_locator:locate_all_blocks(parsed_blocks, file_content)

    local location_result = located_blocks[1].location_result

    -- Verify all expected fields are present
    expect.equality(type(location_result.found), "boolean")
    expect.equality(type(location_result.start_line), "number")
    expect.equality(type(location_result.end_line), "number")
    expect.equality(type(location_result.overall_score), "number")
    expect.equality(type(location_result.overall_match_type), "string")
    expect.equality(type(location_result.confidence), "number")
    expect.equality(type(location_result.found_content), "string")
    expect.equality(type(location_result.found_lines), "table")
    expect.equality(type(location_result.line_details), "table")

    -- Verify content fields match
    eq(location_result.found_content, "target content")
    eq(vim.deep_equal(location_result.found_lines, { "target content" }), true)
end

-- Group 2: Addition Block Handling
T["addition_blocks"] = new_set()

T["addition_blocks"]["empty_search_replaces_entire_file"] = function()
    local diff_content = [[<<<<<<< SEARCH
=======
// New file content
function main() {
    return "hello world";
}
>>>>>>> REPLACE]]

    local file_content = [[// Old file content
function old_main() {
    return "old value";
}]]

    local parsed_blocks = _G.diff_parser:parse(diff_content)
    local located_blocks = _G.block_locator:locate_all_blocks(parsed_blocks, file_content)

    eq(#located_blocks, 1)
    local located_block = located_blocks[1]

    -- Should succeed for addition blocks
    eq(located_block.location_result.found, true)

    -- Should span entire file
    eq(located_block.location_result.start_line, 1)
    eq(located_block.location_result.end_line, 4) -- All lines in file

    -- Should be exact match type for addition blocks
    eq(located_block.location_result.overall_match_type, _G.types.OVERALL_MATCH_TYPE.exact)
    eq(located_block.location_result.overall_score, 1.0)
    eq(located_block.location_result.confidence, 100)

    -- Should contain the entire file content
    eq(located_block.location_result.found_content, file_content)
end

-- Group 3: Location Result Processing
T["location_result_processing"] = new_set()

T["location_result_processing"]["successful_location_result_transformation"] = function()
    local diff_content = [[<<<<<<< SEARCH
function process(data){
    return data.value;
}
=======
function process(data)
    return data.newValue
end
>>>>>>> REPLACE]]

    local file_content = [[function process(data) {
    return data.value;
}]]

    local parsed_blocks = _G.diff_parser:parse(diff_content)
    local located_blocks = _G.block_locator:locate_all_blocks(parsed_blocks, file_content)

    eq(#located_blocks, 1)
    local located_block = located_blocks[1]
    local location_result = located_block.location_result

    -- Verify all BlockLocationResult fields are populated correctly
    eq(location_result.found, true)
    eq(type(location_result.start_line), "number")
    eq(type(location_result.end_line), "number")
    eq(type(location_result.overall_score), "number")
    eq(type(location_result.overall_match_type), "string")
    eq(type(location_result.confidence), "number")
    eq(type(location_result.found_content), "string")
    eq(type(location_result.found_lines), "table")
    eq(type(location_result.line_details), "table")
    eq(location_result.error, nil) -- Should be nil for successful location

    -- Check that content fields are properly populated
    expect.equality(#location_result.found_content > 0, true)
    expect.equality(#location_result.found_lines > 0, true)
    expect.equality(#location_result.line_details > 0, true)
end

T["location_result_processing"]["failed_location_result_transformation"] = function()
    local diff_content = [[<<<<<<< SEARCH
nonexistent_function() {
    return impossible_value;
}
=======
replacement_function() {
    return new_value;
}
>>>>>>> REPLACE]]

    local file_content = [[function real_function() {
    return actual_value;
}]]

    local parsed_blocks = _G.diff_parser:parse(diff_content)
    local located_blocks = _G.block_locator:locate_all_blocks(parsed_blocks, file_content)

    eq(#located_blocks, 1)
    local located_block = located_blocks[1]
    local location_result = located_block.location_result

    -- Verify failed location result structure
    eq(location_result.found, false)
    eq(type(location_result.error), "string")
    expect.equality(location_result.error:match("No suitable match found") ~= nil, true)

    -- -- Failed results should return the best match
    eq(location_result.start_line, 1)
    eq(location_result.end_line, 3)
    eq(location_result.found_content:match("real_function") ~= nil, true)
    -- Should have overall score even if failed
    eq(type(location_result.overall_score), "number")
end

T["location_result_processing"]["line_details_preservation"] = function()
    local diff_content = [[<<<<<<< SEARCH
function test()
  return value
=======
function test()
  return newValue
>>>>>>> REPLACE]]

    local file_content = [[function test() {
  return value;
}]]

    local parsed_blocks = _G.diff_parser:parse(diff_content)
    local located_blocks = _G.block_locator:locate_all_blocks(parsed_blocks, file_content)

    local location_result = located_blocks[1].location_result

    -- Should have line details with proper structure
    expect.equality(#location_result.line_details > 0, true)

    for _, line_detail in ipairs(location_result.line_details) do
        -- Verify LineMatchDetail structure
        eq(type(line_detail.line_number), "number")
        eq(type(line_detail.expected_line), "string")
        eq(type(line_detail.found_line), "string")
        eq(type(line_detail.line_score), "number")
        eq(type(line_detail.line_match_type), "string")
        eq(type(line_detail.differences), "table")

        -- Verify ranges
        expect.equality(line_detail.line_number >= location_result.start_line, true)
        expect.equality(line_detail.line_number <= location_result.end_line, true)
        expect.equality(line_detail.line_score >= 0.0 and line_detail.line_score <= 1.0, true)
    end
end

T["location_result_processing"]["fuzzy_match_metadata_preservation"] = function()
    local diff_content = [[<<<<<<< SEARCH
function calculateResult(input)
=======
function calculateResult(data)
>>>>>>> REPLACE]]

    local file_content = [[function calculateResults(input) {
    return process(input);
}]]

    local parsed_blocks = _G.diff_parser:parse(diff_content)
    local located_blocks = _G.block_locator:locate_all_blocks(parsed_blocks, file_content)

    local location_result = located_blocks[1].location_result

    -- Should be a fuzzy match
    eq(location_result.found, true)
    expect.equality(location_result.overall_match_type ~= _G.types.OVERALL_MATCH_TYPE.exact, true)
    expect.equality(location_result.overall_score < 1.0, true)
    expect.equality(location_result.confidence < 100, true)

    -- Line details should show fuzzy matching information
    expect.equality(#location_result.line_details > 0, true)
    local line_detail = location_result.line_details[1]
    expect.equality(line_detail.line_match_type ~= _G.types.LINE_MATCH_TYPE.exact, true)
    expect.equality(#line_detail.differences >= 0, true) -- May have difference information
end

T["location_result_processing"]["content_consistency"] = function()
    local diff_content = [[<<<<<<< SEARCH
line one
line two
line three
=======
updated line one
updated line two
updated line three
>>>>>>> REPLACE]]

    local file_content = [[prefix
line one
line two
line three
suffix]]

    local parsed_blocks = _G.diff_parser:parse(diff_content)
    local located_blocks = _G.block_locator:locate_all_blocks(parsed_blocks, file_content)

    local location_result = located_blocks[1].location_result

    -- Verify content consistency between different representations
    eq(location_result.start_line, 2)
    eq(location_result.end_line, 4)

    -- found_content should be the concatenated found_lines
    local expected_content = table.concat(location_result.found_lines, "\n")
    eq(location_result.found_content, expected_content)

    -- found_lines should match the actual file lines in that range
    eq(vim.deep_equal(location_result.found_lines, { "line one", "line two", "line three" }), true)

    -- Line details should cover all lines in the range
    eq(#location_result.line_details, 3)
    for i, line_detail in ipairs(location_result.line_details) do
        eq(line_detail.line_number, location_result.start_line + i - 1)
        eq(line_detail.found_line, location_result.found_lines[i])
    end
end

return T
