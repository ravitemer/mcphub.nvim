--[[
*MCP Servers Tool*
This tool can be used to call tools and resources from the MCP Servers.
--]]
local xml2lua = require("codecompanion.utils.xml.xml2lua")
local M = {}

local tool_schemas = {
    use_mcp_tool = {
        tool = {
            _attr = {
                name = "use_mcp_tool",
            },
            action = {
                server_name = "<![CDATA[weather-server]]>",
                tool_name = "<![CDATA[get_forecast]]>",
                tool_input = '<![CDATA[{"city": "San Francisco", "days": 5}]]>',
            },
        },
    },
    access_mcp_resource = {
        tool = {
            _attr = {
                name = "access_mcp_resource",
            },
            action = {
                server_name = "<![CDATA[weather-server]]>",
                uri = "<![CDATA[weather://sanfrancisco/current]]>",
            },
        },
    },
}

function M.system_prompt(hub)
    local prompts = hub:generate_prompts({
        use_mcp_tool_example = xml2lua.toXml({ tools = { tool_schemas.use_mcp_tool } }),
        access_mcp_resource_example = xml2lua.toXml({ tools = { tool_schemas.access_mcp_resource } }),
    })
    return string.format(
        [[### `use_mcp_tool` Tool and `access_mcp_resource` Tool

⚠️ **CRITICAL INSTRUCTIONS - READ CAREFULLY** ⚠️

The Model Context Protocol (MCP) enables communication with locally running MCP servers that provide additional tools and resources to extend your capabilities.

1. **ONE TOOL CALL PER RESPONSE**:
   - YOU MUST MAKE ONLY ONE TOOL CALL PER RESPONSE
   - NEVER chain multiple tool calls in a single response
   - For tasks requiring multiple tools, you MUST wait for the result of each tool before proceeding

2. **ONLY USE AVAILABLE SERVERS AND TOOLS**:
   - ONLY use the servers and tools listed in the "Connected MCP Servers" section below
   - DO NOT invent or hallucinate server names, tool names, or resource URIs
   - If a requested server or tool is not listed in "Connected MCP Servers", inform the user it's not available

3. **GATHER REQUIRED INFORMATION FIRST**:
   - NEVER use placeholder values for parameters e.g {"id": "YOUR_ID_HERE"}
   - NEVER guess or make assumptions about parameters like IDs, or file paths etc
   - Before making tool calls:
     * CALL other tools to get the required information first e.g listing available files or database pages before writing to them.
     * ASK the user for needed information if not provided

4. **Dependent Operations Workflow**:
   - Step 1: Make ONE tool call
   - Step 2: WAIT for the user to show you the result
   - Step 3: Only THEN, in a NEW response, make the next tool call

5. **Forbidden Pattern Examples**:
   ❌ DO NOT DO THIS: Multiple <tools> blocks in one response
   ❌ DO NOT DO THIS: Using placeholder values or made-up while calling tools e.g {"id": "YOUR_ID_HERE"}

6. **Correct Pattern Examples**:
   ✅ DO THIS: List available resources first → Wait for result → Use correct parameters
   ✅ DO THIS: Verify parameters are correct before making tool calls
   ✅ DO THIS: Ask for clarification when user requests are unclear

7. **XML Structure Requirements**:
   - Format: ```xml<tools><tool name="tool_name"></tool></tools>```
   - When using the <tool name="use_mcp_tool"></tool> tool: The following are a MUST
     * The server_name child tag must be provided with a valid server name
     * The tool_name child tag must be provided with a valid tool name of the server_name
     * The tool_input child tag must be always be a JSON object with the required parameters from the tool_name's inputSchema
       e.g: %s
   - When using the <tool name="access_mcp_resource"></tool> tool: The following are a MUST
     * The server_name child tag must be provided with a valid server name
     * The uri attribute child tag be provided with a valid resource URI in the server_name


8. **Examples**:

%s

%s


]],
        '<![CDATA[{"city": "San Francisco", "days": 5}]]>',
        prompts.use_mcp_tool,
        prompts.access_mcp_resource
    )
end

return M
