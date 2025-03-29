local mcphub = require("mcphub")

-- Import individual tools and resources
local buffer_resource = require("mcphub.native.neovim.files.buffer")
local environment_resource = require("mcphub.native.neovim.files.environment")
local file_tools = require("mcphub.native.neovim.files.operations")
local write_tools = require("mcphub.native.neovim.files.write")
-- local replace_tools = require("mcphub.native.neovim.files.replace")
local search_tools = require("mcphub.native.neovim.files.search")

-- Register all file-related tools and resources
local function setup()
    -- Register resources
    mcphub.add_resource("neovim", buffer_resource)
    mcphub.add_resource("neovim", environment_resource)

    -- Register file operation tools
    for _, tool in ipairs(file_tools) do
        mcphub.add_tool("neovim", tool)
    end

    -- Register write tools
    for _, tool in ipairs(write_tools) do
        mcphub.add_tool("neovim", tool)
    end

    -- Register search tools
    for _, tool in ipairs(search_tools) do
        mcphub.add_tool("neovim", tool)
    end

    -- Register replace tool
    -- mcphub.add_tool("neovim", replace_tools)
end

setup()
-- return {
--     setup = setup,
-- }
