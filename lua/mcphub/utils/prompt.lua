---@brief [[
--- Utility functions for generating MCP system prompts.
--- Parts of the prompts are inspired from RooCode repository:
--- https://github.com/RooVetGit/Roo-Code
---@brief ]]
local M = {}
local State = require("mcphub.state")
local log = require("mcphub.utils.log")
local native = require("mcphub.native")
local validation = require("mcphub.utils.validation")

---@return string
local function get_header()
    return [[
# MCP SERVERS

The Model Context Protocol (MCP) enables communication between the system and locally running MCP servers that provide additional tools and resources to extend your capabilities.
]]
end

---@param server_name string
---@return string
local function format_custom_instructions(server_name)
    local is_native = native.is_native_server(server_name)
    local server_config = (is_native and State.native_servers_config[server_name] or State.servers_config[server_name])
        or {}
    local custom_instructions = server_config.custom_instructions or {}

    if custom_instructions.text and custom_instructions.text ~= "" and not custom_instructions.disabled then
        return string.format("\n\n### Instructions for `%s` server\n\n" .. custom_instructions.text, server_name)
    end
    return ""
end

---@param def MCPServer|NativeServer|MCPTool|MCPResource|MCPResourceTemplate
---@return string
function M.get_description(def)
    local description = def.description or ""
    if type(description) == "function" then
        local ok, desc = pcall(description, def)
        if not ok then
            description = "Failed to get description :" .. (desc or "")
        else
            description = desc or ""
        end
    end
    return description
end

---@param def MCPTool
---@return table
function M.get_inputSchema(def)
    local base = {
        type = "object",
        properties = {},
    }
    local inputSchema = def.inputSchema
    if not inputSchema or (type(inputSchema) == "table" and not next(inputSchema)) then
        inputSchema = base
    end
    local parsedSchema = inputSchema
    if type(parsedSchema) == "function" then
        local ok, schema = pcall(parsedSchema, def)
        if not ok then
            local err = "Error in inputSchema function: " .. tostring(schema)
            log.error(err)
            parsedSchema = base
        else
            parsedSchema = schema or base
        end
    end
    local res = validation.validate_inputSchema(parsedSchema, def.name)
    if not res.ok then
        local err = "Error in inputSchema function: " .. tostring(res.error)
        log.error(err)
        return base
    end
    return parsedSchema
end

---@param tools MCPTool[]
---@return string
local function format_tools(tools)
    if not tools or #tools == 0 then
        return ""
    end

    local result = "\n\n### Available Tools"
    for _, tool in ipairs(tools) do
        result = result .. string.format("\n\n- %s: %s", tool.name, M.get_description(tool))
        local inputSchema = M.get_inputSchema(tool)
        result = result .. "\n    Input Schema:\n    " .. vim.inspect(inputSchema):gsub("\n", "\n    ")
    end
    return result
end

---@diagnostic disable-next-line: unused-function
local function remove_functions(obj)
    if type(obj) ~= "table" then
        return obj
    end
    local new_obj = {}
    for k, v in pairs(obj) do
        if type(v) ~= "function" then
            new_obj[k] = remove_functions(v)
        end
    end
    return new_obj
end

---@param resources MCPResource[]
---@param templates MCPResourceTemplate[]
---@return string
local function format_resources(resources, templates)
    local result = ""
    if resources and #resources > 0 then
        result = result .. "\n\n### Available Resources"
        for _, resource in ipairs(resources) do
            result = result
                .. string.format("\n\n- %s%s", resource.uri, resource.mimeType and " (" .. resource.mimeType .. ")" or "")
            local desc = M.get_description(resource)
            result = result .. "\n  " .. (resource.name or "") .. (desc == "" and "" or "\n  " .. desc)
            -- result = result .. "\n\n" .. vim.inspect(remove_functions(resource))
        end
    end
    if templates and #templates > 0 then
        result = result .. "\n\n### Available Resource Templates"
        for _, template in ipairs(templates) do
            result = result .. string.format("\n\n- %s", template.uriTemplate)
            local desc = M.get_description(template)
            result = result .. "\n  " .. (template.name or "") .. (desc == "" and "" or "\n  " .. desc)
            -- result = result .. "\n\n" .. vim.inspect(remove_functions(template))
        end
    end
    return result
end

--- Get the use_mcp_tool section of the prompt
---@param example? string Optional custom XML example block
---@return string The formatted prompt section
function M.get_use_mcp_tool_prompt(example)
    local default_example = [[<use_mcp_tool>
<server_name>weather-server</server_name>
<tool_name>get_forecast</tool_name>
<arguments>
{
  "city": "San Francisco",
  "days": 5
}
</arguments>
</use_mcp_tool>]]

    return string.format(
        [[
## use_mcp_tool

Description: Request to use a tool provided by a connected MCP server. Each MCP server can provide multiple tools with different capabilities. Tools have defined input schemas that specify required and optional parameters.
Parameters:
- server_name: (required) The name of the MCP server providing the tool
- tool_name: (required) The name of the tool to execute
- arguments: (required) A JSON object containing the tool's input parameters, following the tool's input schema

Example: Requesting to use an MCP tool

%s]],
        example or default_example
    )
end

--- Get the access_mcp_resource section of the prompt
---@param example? string Optional custom XML example block
---@return string The formatted prompt section
function M.get_access_mcp_resource_prompt(example)
    local default_example = [[<access_mcp_resource>
<server_name>weather-server</server_name>
<uri>weather://san-francisco/current</uri>
</access_mcp_resource>]]

    return string.format(
        [[
## access_mcp_resource

Description: Request to access a resource provided by a connected MCP server. Resources represent data sources that can be used as context, such as files, API responses, or system information.
Parameters:
- server_name: (required) The name of the MCP server providing the resource
- uri: (required) The URI identifying the specific resource to access

Example: Requesting to access an MCP resource

%s]],
        example or default_example
    )
end

---@param server MCPServer
---@return string
function M.server_to_text(server)
    local text = ""
    -- Add server section
    text = text .. string.format("## %s", server.name)
    local is_disabled = server.status == "disabled"
    if is_disabled then
        text = text .. " (Disabled)"
    end
    local desc = M.get_description(server)
    -- Add description
    text = text .. (desc == "" and "" or "\n" .. desc)
    if is_disabled then
        return text
    end
    if
        server.capabilities
        and (
            (server.capabilities.tools and #server.capabilities.tools > 0)
            or (server.capabilities.resources and #server.capabilities.resources > 0)
            or (server.capabilities.resourceTemplates and #server.capabilities.resourceTemplates > 0)
        )
    then
        -- Add custom instructions if any
        text = text .. format_custom_instructions(server.name)

        -- Add capabilities
        text = text .. format_tools(server.capabilities.tools)
        text = text .. format_resources(server.capabilities.resources, server.capabilities.resourceTemplates)
    else
        text = text .. "\n(No tools or resources available)"
    end
    return text
end

---@param servers MCPServer[]
---@param add_example boolean
---@param enable_toggling_mcp_servers boolean
---@return string
function M.get_active_servers_prompt(servers, add_example, enable_toggling_mcp_servers)
    add_example = add_example ~= false
    enable_toggling_mcp_servers = enable_toggling_mcp_servers ~= false
    local prompt = get_header()

    ---@type MCPServer[]
    local connected_servers = vim.tbl_filter(function(s)
        return s.status == "connected"
    end, servers)

    ---@type MCPServer[]
    local disabled_servers = vim.tbl_filter(function(s)
        return s.status == "disabled"
    end, servers)

    prompt = prompt .. "\n# Connected MCP Servers"

    prompt = prompt
        .. "\n\nWhen a server is connected, you can use the server's tools via the `use_mcp_tool` tool, "
        .. "and access the server's resources via the `access_mcp_resource` tool.\nNote: Server names are case sensitive and you should always use the exact full name like `Firecrawl MCP` or `src/user/main/time-mcp` etc \n\n"
    if #connected_servers == 0 then
        prompt = prompt .. "(No connected MCP servers)\n\n"
    else
        for _, server in ipairs(connected_servers) do
            prompt = prompt .. M.server_to_text(server) .. "\n\n"
        end
    end

    -- instead of removing the whole disabled section, if we dont want auto toggling we set (NO disabled servers) to avoid llm hallucinating server names
    prompt = prompt .. "# Disabled MCP Servers\n\n"
    prompt = prompt
        .. "When a server is disabled, it will not be able to provide tools or resources. You can start one of the following disabled servers by using the `toggle_mcp_server` tool on `mcphub` MCP Server if it is connected using `use_mcp_tool`\n\n"
    if not enable_toggling_mcp_servers or #disabled_servers == 0 then
        prompt = prompt .. "(No disabled MCP servers)\n\n"
    else
        for _, server in ipairs(disabled_servers) do
            prompt = prompt .. M.server_to_text(server) .. "\n\n"
        end
    end
    local toggle_example = [[## Toggling a MCP Server

When you need to start a disabled MCP Server or vice-versa, use the `toggle_mcp_server` tool on `mcphub` MCP Server using `use_mcp_tool`:

CRITICAL: You need to use the `use_mcp_tool` tool to call the `toggle_mcp_server` tool on `mcphub` MCP Server when `mcphub` server is "Connected" else ask the user to enable `mcphub` server.

Pseudocode:

use_mcp_tool
  server_name: "mcphub"
  tool_name: "toggle_mcp_server"
  tool_input: 
    server_name: string (One of the available server names to start or stop)
    action: string (one of `start` or `stop`)
]]

    local example = [[


# Examples: 

## `use_mcp_tool`

When you need to call a tool on an MCP Server, use the `use_mcp_tool` tool:

Pseudocode:

use_mcp_tool
  server_name: string (One of the available server names)
  tool_name: string (name of the tool in the server to call)
  tool_input: object (Arguments for the tool call)

## `access_mcp_resource`

When you need to access a resource from a MCP Server, use the `access_mcp_resource` tool:

Pseudocode:

access_mcp_resource
  server_name: string (One of the available server names)
  uri: string (uri for the resource)

]]

    if enable_toggling_mcp_servers then
        example = example .. toggle_example
    end

    return prompt .. (add_example and example or "")
end

---@param response {result: {messages: {role:string, content: table}[]}}|nil
---@return {messages : {role:"user"| "assistant"|"system", output: MCPResponseOutput}[]}
function M.parse_prompt_response(response)
    if response == nil then
        return { messages = {} }
    end
    local result = response.result or {}
    local messages = {}
    for _, v in ipairs(result.messages or {}) do
        local output = { text = "", images = {}, blobs = {}, audios = {} }
        local content = v.content
        if content.type == "text" then
            output.text = content.text
        elseif content.type == "image" then
            table.insert(output.images, {
                data = content.data,
                mimeType = content.mimeType or "application/octet-stream",
            })
        elseif content.type == "audio" then
            table.insert(output.audios, {
                data = content.data,
                mimeType = content.mimeType or "application/octet-stream",
            })
        elseif content.type == "blob" then
            table.insert(output.blobs, {
                data = content.data,
                mimeType = content.mimeType or "application/octet-stream",
            })
        elseif content.type == "resource" then
            -- Handle resource content by treating it as a resource response
            local resource_result = M.parse_resource_response({
                result = {
                    contents = { content.resource },
                },
            })
            output.text = resource_result.text
            vim.list_extend(output.images, resource_result.images)
            vim.list_extend(output.blobs, resource_result.blobs)
            vim.list_extend(output.audios, resource_result.audios)
        end
        table.insert(messages, {
            role = v.role,
            output = output,
        })
    end
    return {
        messages = messages,
    }
end

---@param response? table
---@return MCPResponseOutput
function M.parse_tool_response(response)
    if response == nil then
        return { error = nil, text = "", images = {}, blobs = {}, audios = {} }
    end

    local result = response.result or {}
    local output = { text = "", images = {}, blobs = {}, audios = {}, error = nil }
    local images = {}
    local blobs = {}
    local texts = {}
    local audios = {}

    -- parse tool response
    for _, v in ipairs(result.content or {}) do
        local type = v.type
        if type == "text" then
            table.insert(texts, v.text)
        elseif type == "image" then
            table.insert(images, {
                data = v.data,
                mimeType = v.mimeType or "application/octet-stream",
            })
        elseif type == "blob" then
            table.insert(output.blobs, {
                data = v.data,
                mimeType = v.mimeType or "application/octet-stream",
            })
        elseif type == "audio" then
            table.insert(audios, {
                data = v.data,
                mimeType = v.mimeType or "application/octet-stream",
            })
        elseif type == "resource" and v.resource then
            -- Handle resource content by treating it as a resource response
            local resource_result = M.parse_resource_response({
                result = {
                    contents = { v.resource },
                },
            })
            -- Merge the results
            table.insert(texts, resource_result.text)
            vim.list_extend(images, resource_result.images)
            vim.list_extend(blobs, resource_result.blobs)
            vim.list_extend(audios, resource_result.audios)
        end
    end

    -- Combine all text with newlines
    output.text = table.concat(texts, "\n")
    if result.isError then
        output.error = output.text
        output.text = "The tool run failed with error.\n" .. output.text
    end
    output.images = images
    output.blobs = blobs
    output.audios = audios

    return output
end

---@param response? table
---@return MCPResponseOutput
function M.parse_resource_response(response)
    if response == nil then
        return { text = "", images = {}, blobs = {} }
    end

    local result = response.result or {}
    local output = { text = "", images = {}, blobs = {} }
    local images = {}
    local blobs = {}
    local texts = {}
    local audios = {}

    for _, content in ipairs(result.contents or {}) do
        if content.uri then
            if content.blob then
                -- Handle blob data based on mimetype
                if content.mimeType and content.mimeType:match("^image/") then
                    -- It's an image
                    table.insert(images, {
                        data = content.blob,
                        mimeType = content.mimeType,
                    })
                elseif content.mimeType and content.mimeType:match("^audio/") then
                    -- It's an audio blob
                    table.insert(audios, {
                        data = content.blob,
                        mimeType = content.mimeType,
                    })
                else
                    -- It's a binary blob
                    table.insert(blobs, {
                        data = content.blob,
                        mimeType = content.mimeType or "application/octet-stream",
                        uri = content.uri,
                    })
                    -- Add blob info to text
                    table.insert(
                        texts,
                        string.format(
                            "Resource %s: <Binary data of type %s>",
                            content.uri,
                            content.mimeType or "application/octet-stream"
                        )
                    )
                end
            elseif content.text then
                -- Text content
                table.insert(texts, string.format("Resource %s:\n%s", content.uri, content.text))
            end
        end
    end

    output.text = table.concat(texts, "\n\n")
    output.images = images
    output.blobs = blobs
    output.audios = audios
    return output
end

--- Get a standardized installation prompt for marketplace servers
---@param details table The server details including name, mcpId, githubUrl, etc
---@return string The formatted installation prompt
function M.get_marketplace_server_prompt(details)
    -- Get OS info and paths
    local os_info = vim.uv.os_uname()
    local home = vim.fn.expand("~")
    local servers_path = home .. "/.mcphub/servers"

    -- Get current config content
    local config_result = validation.validate_config_file(details.config_file)
    local config_content = config_result.content or "{}"

    -- Build installation prompt
    return string.format(
        [[
Model Context Protocol (MCP) servers enable communication between LLMs and external systems by providing tools and resources through a standardized interface. This installation will set up an MCP server to extend the system's capabilities.

Task: Set up the MCP server from %s

Current Config File Content:
%s

Environment Details:
- Operating System: %s
- MCP Servers Directory Path: %s (create subdirectories here if required)
- Config File Path: %s

Server Details:
- Name: %s
- MCP ID: %s (use this as server name in config)
- GitHub URL: %s

Installation Instructions:
1. Review README instructions below
2. Follow setup steps from README 
3. Ask the user to provide any env variables or details required for the server configuration.
4. Update config at %s
5. Ask the user to Restart MCPHub by opening the UI and pressing "R" to restart the hub with updated config and ask the user to provide you with mcp tool if not already provided.

README Content:
-------------
%s
-------------]],
        details.githubUrl or "unknown",
        config_content,
        vim.inspect(os_info),
        servers_path,
        details.config_file,
        details.name,
        details.mcpId,
        details.githubUrl or "N/A",
        details.config_file,
        details.readmeContent or "No README available"
    )
end

--- Get the troubleshooting guide for MCPHub
--- @return string|nil The troubleshooting guide content or nil if not found
function M.get_troubleshooting_guide()
    local source_path = debug.getinfo(1, "S").source:sub(2) -- Remove '@' prefix
    local base_path = vim.fn.fnamemodify(source_path, ":h:h:h:h") -- Go up three levels from prompt.lua
    local guide_path = base_path .. "/doc/other/troubleshooting.md"
    local f = io.open(guide_path)
    if not f then
        return nil
    end

    local content = f:read("*all")
    f:close()

    return content
end

--- Get the native server creation prompt from the guide file
---@return string|nil The native server guide content or nil if not found
function M.get_native_server_prompt()
    -- Use source file path to find the guide
    local source_path = debug.getinfo(1, "S").source:sub(2) -- Remove '@' prefix
    local base_path = vim.fn.fnamemodify(source_path, ":h:h") -- Go up three levels from prompt.lua
    local guide_path = base_path .. "/native/NATIVE_SERVER_LLM.md"
    local f = io.open(guide_path)
    if not f then
        return nil
    end

    local content = f:read("*all")
    f:close()

    return content
end

--- Get mcphub.nvim plugin documentation intended for llms
---@return string|nil The plugin docs content or nil if not found
function M.get_plugin_docs()
    local source_path = debug.getinfo(1, "S").source:sub(2)
    local base_path = vim.fn.fnamemodify(source_path, ":h:h:h:h")
    local guide_path = base_path .. "/README.md"
    local f = io.open(guide_path)
    if not f then
        return nil
    end
    local content = f:read("*all")
    f:close()
    return content
end

--- Get the changelog for the mcphub.nvim plugin
--- @return string|nil The changelog content or nil if not found
function M.get_plugin_changelog()
    local source_path = debug.getinfo(1, "S").source:sub(2)
    local base_path = vim.fn.fnamemodify(source_path, ":h:h:h:h")
    local guide_path = base_path .. "/CHANGELOG.md"
    local f = io.open(guide_path)
    if not f then
        return nil
    end
    local content = f:read("*all")
    f:close()
    return content
end

return M
