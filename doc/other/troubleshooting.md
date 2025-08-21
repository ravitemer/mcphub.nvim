# Troubleshooting

> [!IMPORTANT]
> Join our [discord](https://discord.gg/NTqfxXsNuN) channel for quick help.


## Quick Fix

Try restarting MCPHub by pressing `R` key in the `:MCPHub` interface. This resolves most common issues. 


## Checkhealth

Run `:checkhealth mcphub` in Neovim to check for common issues

![Image](https://github.com/user-attachments/assets/5588b76e-53e3-49d6-8ae5-9a5d3ed2c7fb)

## Environment Requirements

- Ensure these are installed as they're required by most MCP servers:
 ```bash
 node --version    # Should be >= 18.0.0
 python --version  # Should be installed
 uvx --version    # Should be installed
 ```
- Most server commands use `npx` or `uvx` - verify these work in your terminal
- Neovim must be built with LuaJIT (not PUC Lua 5.1)

## Configuration File

- Ensure config path is absolute
- Verify file contains valid JSON with `mcpServers` key
- Check server-specific configuration requirements
- Validate server command and args are correct for your system

## MCP Server Issues

- Check server logs in MCPHub UI (Logs view)
- Set logging to file:

```lua
{
    level = vim.log.levels.DEBUG,
    to_file = true,
    file_path = vim.fn.expand("~/mcphub.log"),
}
```
- Test tools and resources individually to isolate issues
- Validate server configurations using either:
 - [MCP Inspector](https://github.com/modelcontextprotocol/inspector): GUI tool for verifying server operation
 - [mcp-cli](https://github.com/wong2/mcp-cli): Command-line tool for testing servers with config files

## LLM Model Issues

If the LLM isn't making correct tool calls:

1. **Schema Support**
   - Models with function calling support (like claude-3.5) work best with Avante's schema format
   - Only top-tier models handle XML-based tool formats correctly
   - Consider upgrading to a better model if seeing incorrect tool usage

2. **Common Tool Call Issues**
   - Missing `action` field
   - Incorrect `server_name`
   - Missing `tool_name` or `uri`
   - Malformed arguments

3. **Recommended Models**
   - Claude 3.5 Sonnet
   - Claude 3.7 Sonnet
   - Gemini 2.5 Pro
   - gpt 4.1
   - Mistral Large



## Port Issues

- If you get `EADDRINUSE` error, kill the existing process:
 ```bash
 lsof -i :[port]  # Find process ID
 kill [pid]       # Kill the process
 ```


## Need Help?

- Join our [discord](https://discord.gg/NTqfxXsNuN) channel for quick help.
<!-- - Try testing it with [minimal.lua](https://gist.github.com/ravitemer/c85d69542bdfd1a45c6a9849301e4388)  -->
- Feel free to open an [Issue](https://github.com/ravitemer/mcphub.nvim/issues) for bugs or doubts
- Create a [Discussion](https://github.com/ravitemer/mcphub.nvim/discussions) for questions, showcase, or feature requests

