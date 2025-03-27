--[[
*MCP Servers Tool*
This tool can be used to call tools and resources from the MCP Servers.
--]]
local config = require("codecompanion.config")
local xml2lua = require("codecompanion.utils.xml.xml2lua")

local function parse_params(action)
    local action_name = action._attr.type
    local server_name = action.server_name
    local tool_name = action.tool_name
    local json_ok, arguments = pcall(vim.fn.json_decode, action.arguments or "{}")
    if json_ok then
        arguments = arguments or {}
    else
        arguments = {}
    end
    local uri = action.uri
    return {
        action = action_name,
        server_name = server_name,
        tool_name = tool_name,
        uri = uri,
        arguments = arguments,
    }
end
---@class CodeCompanion.Tool
local tool_schema = {
    name = "mcp",
    cmds = {
        function(self, action, input, output_handler)
            local hub = require("mcphub").get_hub_instance()
            local params = parse_params(action)
            if params.action == "use_mcp_tool" then
                --use async call_tool method
                hub:call_tool(params.server_name, params.tool_name, params.arguments, {
                    caller = {
                        type = "codecompanion",
                        codecompanion = self,
                    },
                    parse_response = true,
                    callback = function(res, err)
                        if err or not res then
                            output_handler({ status = "error", data = tostring(err) or "No response from call tool" })
                        elseif res then
                            output_handler({ status = "success", data = res })
                        end
                    end,
                })
            elseif params.action == "access_mcp_resource" then
                -- use async access_resource method
                hub:access_resource(params.server_name, params.uri, {
                    caller = {
                        type = "codecompanion",
                        codecompanion = self,
                    },
                    parse_response = true,
                    callback = function(res, err)
                        if err or not res then
                            output_handler({
                                status = "error",
                                data = tostring(err) or "No response from access resource",
                            })
                        elseif res then
                            output_handler({ status = "success", data = res })
                        end
                    end,
                })
            else
                return {
                    status = "error",
                    data = "Invalid action type",
                }
            end
        end,
    },
    schema = {
        {
            tool = {
                _attr = {
                    name = "mcp",
                },
                action = {
                    _attr = {
                        type = "use_mcp_tool",
                    },
                    server_name = "<![CDATA[weather-server]]>",
                    tool_name = "<![CDATA[get_forecast]]>",
                    arguments = '<![CDATA[{"city": "San Francisco", "days": 5}]]>',
                },
            },
        },
        {
            tool = {
                _attr = {
                    name = "mcp",
                },
                action = {
                    _attr = {
                        type = "access_mcp_resource",
                    },
                    server_name = "<![CDATA[weather-server]]>",
                    uri = "<![CDATA[weather://sanfrancisco/current]]>",
                },
            },
        },
    },

    system_prompt = function(schema)
        -- get the running hub instance
        local hub = require("mcphub").get_hub_instance()
        return string.format(
            [[### MCP Tool

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
   - Format: ```xml<tools><tool name="mcp"><action type="...">...</action></tool></tools>```
   - ALWAYS use name="mcp" for the tool tag
   - Inside the tool must be exactly ONE <action> tag with type="use_mcp_tool" OR type="access_mcp_resource"
   - The arguments attribute must be always be a JSON object with the required parameters for the tool call
     e.g: %s
   - Except for optional attributes, ALL required parameters must be provided for actions.


8. **Available Actions**:
   The only valid action types are "use_mcp_tool" and "access_mcp_resource":

%s

%s

%s]],
            '<![CDATA[{"city": "San Francisco", "days": 5}]]>',
            hub:get_use_mcp_tool_prompt(xml2lua.toXml({
                tools = { schema[1] },
            })), -- gets the prompt for the use_mcp_tool action
            hub:get_access_mcp_resource_prompt(xml2lua.toXml({
                tools = { schema[2] },
            })), -- gets the prompt for the access_mcp_resource action
            hub:get_active_servers_prompt() -- generates prompt from currently running mcp servers
        )
    end,
    output = {
        ---Approve the command to be run
        ---@param self CodeCompanion.Tools The tool object
        ---@param agent table
        ---@return string
        prompt = function(self, agent)
            local action = agent.request.action
            local utils = require("mcphub.extensions.utils")
            return utils.get_mcp_tool_prompt(parse_params(action))
        end,
        rejected = function(self)
            local action = self.tool.request.action
            local action_name = action._attr.type
            self.chat:add_buf_message({
                role = config.constants.USER_ROLE,
                content = string.format("I've rejected the request to use the `%s` action.\n", action_name),
            })
        end,
        error = function(self, action, stderr)
            local action_name = action._attr.type
            stderr = stderr or ""
            if type(stderr) == "table" then
                stderr = vim.inspect(stderr)
            end
            self.chat:add_buf_message({
                role = config.constants.USER_ROLE,
                content = string.format(
                    [[ERROR: The `%s` call failed with the following error:
<error>
%s
</error>
]],
                    action_name,
                    stderr
                ),
            }, {
                visible = false,
            })

            -- self.chat:add_buf_message({
            --     role = config.constants.USER_ROLE,
            --     content = "I've shared the error message from the `mcp` tool with you.\n",
            -- })
        end,
        success = function(self, action, output)
            local result = output[1]
            local action_name = action._attr.type

            -- Show text content if present
            if result.text and result.text ~= "" then
                self.chat:add_buf_message({
                    role = config.constants.USER_ROLE,
                    content = string.format(
                        [[The `%s` call returned the following text: 
%s]],
                        action_name,
                        result.text
                    ),
                })
            end

            -- Show image content if present
            -- if result.images and #result.images > 0 then
            -- TODO: Add image support when codecompanion supports it
            -- self.chat:add_message({
            --     role = config.constants.USER_ROLE,
            --     content = vim.tbl_map(function(image)
            --         return {
            --             type = "image",
            --             base64 = string.format("data:%s;base64,%s", image.mimeType, image.data),
            --         }
            --     end, result.images),
            -- }, { visible = false })
            -- end

            -- self.chat:add_buf_message({
            --     role = config.constants.USER_ROLE,
            --     content = "I've shared the result of the `mcp` tool with you.\n",
            -- })
        end,
    },
}

return tool_schema
