<div align="center" markdown="1">
   <sup>Special thanks to:</sup>
   <br>
   <br>
   <a href="https://www.warp.dev/mcp-hub-nvim">
      <img alt="Warp sponsorship" src="https://github.com/user-attachments/assets/fae9c70d-51de-43fa-af65-c82228ba67f9">
   </a>

### [The Intelligent Terminal](https://www.warp.dev/mcp-hub-nvim)

[Run mcphub.nvim in Warp today](https://www.warp.dev/mcp-hub-nvim)<br>

</div>
<hr>

<div align="center" markdown="1">
<h1> <img width="28px" style="display:inline;" src="https://github.com/user-attachments/assets/5cdf9d69-3de7-458b-a670-5153a97c544a"/> MCP HUB</h1>

[![Lua](https://img.shields.io/badge/Lua-2C2D72?style=flat-square&logo=lua&logoColor=white)](https://www.lua.org)
[![NixOS](https://img.shields.io/badge/NixOS-5277C3?style=flat-square&logo=nixos&logoColor=white)](https://nixos.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Discord](https://img.shields.io/badge/Discord-Join-7289DA?style=flat-square&logo=discord&logoColor=white)](https://discord.gg/NTqfxXsNuN)
</div>

MCP Hub is a MCP client for neovim that seamlessly integrates [MCP (Model Context Protocol)](https://modelcontextprotocol.io/) servers into your editing workflow. It provides an intuitive interface for managing, testing, and using MCP servers with your favorite chat plugins.

![Image](https://github.com/user-attachments/assets/21fe7703-9bc3-4c01-93ce-3230521bd5bf)

## 💜 Sponsors

<!-- sponsors --> <p align="center"> <a href="https://github.com/CryogenicPlanet"><img src="https://github.com/CryogenicPlanet.png" width="60px" alt="CryogenicPlanet" /></a> <a href="https://github.com/yingmanwumen"><img src="https://github.com/yingmanwumen.png" width="60px" alt="yingmanwumen" /></a> <a href="https://github.com/yetone"><img src="https://github.com/yetone.png" width="60px" alt="Yetone" /></a> <a href="https://github.com/omarcresp"><img src="https://github.com/omarcresp.png" width="60px" alt="omarcresp" /></a> <a href="https://github.com/petermoser"><img src="https://github.com/petermoser.png" width="60px" alt="petermoser" /></a> <a href="https://github.com/watsy0007"><img src="https://github.com/watsy0007.png" width="60px" alt="watsy0007" /></a> <a href="https://github.com/kohane27"><img src="https://github.com/kohane27.png" width="60px" alt="kohane27" /></a>  <a href="https://github.com/copleykj"><img src="https://github.com/copleykj.png" width="60px" alt="Kelly Copley" /></a></p><!-- sponsors -->

<p align="center">
  <b>Special thanks to:</b> 
</p>
<p align="center">
  <a href="https://dub.sh/composio-mcp" target="_blank"> <img src="https://composio.dev/wp-content/uploads/2025/01/Composio-logo-25.png" height="30px" alt="Composio.dev logo" />  </a>
</p>

## ✨ Features 

| Category | Feature | Support | Details |
|----------|---------|---------|-------|
| [**Capabilities**](https://modelcontextprotocol.io/specification/2025-03-26/server) ||||
| | Tools | ✅ | Full support |
| | 🔔 Tool List Changed | ✅ | Real-time updates |
| | Resources | ✅ | Full support |
| | 🔔 Resource List Changed | ✅ | Real-time updates |
| | Resource Templates | ✅ | URI templates |
| | Prompts | ✅ | Full support |
| | 🔔 Prompts List Changed | ✅ | Real-time updates |
| | Roots | ❌ | Not supported |
| | Sampling | ❌ | Not supported |
| **MCP Server Transports** ||||
| | [Streamable-HTTP](https://modelcontextprotocol.io/specification/2025-03-26/basic/transports#streamable-http) | ✅ | Primary transport protocol for remote servers |
| | [SSE](https://modelcontextprotocol.io/specification/2025-03-26/basic/transports#backwards-compatibility) | ✅ | Fallback transport for remote servers |
| | [STDIO](https://modelcontextprotocol.io/specification/2025-03-26/basic/transports#stdio) | ✅ | For local servers |
| **Authentication for remote servers** ||||
| | [OAuth](https://modelcontextprotocol.io/specification/2025-03-26/basic/authorization) | ✅ | With PKCE flow |
| | Headers | ✅ | For API keys/tokens |
| **Chat Integration** ||||
| | [Avante.nvim](https://github.com/yetone/avante.nvim) | ✅ | Tools, resources, resourceTemplates, prompts(as slash_commands) |
| | [CodeCompanion.nvim](https://github.com/olimorris/codecompanion.nvim) | ✅ | Tools, resources, templates, prompts (as slash_commands), 🖼 image responses | 
| | [CopilotChat.nvim](https://github.com/CopilotC-Nvim/CopilotChat.nvim) | ✅ | In-built support [Draft](https://github.com/CopilotC-Nvim/CopilotChat.nvim/pull/1029) | 
| **Marketplace** ||||
| | Server Discovery | ✅ | Browse from verified MCP servers |
| | Installation | ✅ | Manual and auto install with AI |
| **Advanced** ||||
| | Smart File-watching | ✅ | Smart updates with config file watching |
| | Multi-instance | ✅ | All neovim instances stay in sync |
| | Shutdown-delay | ✅ | Can run as systemd service with configure delay before stopping the hub |
| | Lua Native MCP Servers | ✅ | Write once , use everywhere. Can write tools, resources, prompts directly in lua |
| | Dev Mode | ✅ | Hot reload MCP servers on file changes for development |

## 🎥 Demos

<div align="center">
<p>
<h4>MCP Hub + <a href="https://github.com/yetone/avante.nvim">Avante</a> + Figma </h4>
<video controls muted src="https://github.com/user-attachments/assets/e33fb5c3-7dbd-40b2-bec5-471a465c7f4d"></video>
</p>
</div>


## 🚀 Getting Started

Visit our [documentation site](https://ravitemer.github.io/mcphub.nvim/) for detailed guides and examples

## 👋 Get Help

- Check out the [Troubleshooting guide](https://ravitemer.github.io/mcphub.nvim/troubleshooting)
- Join our [Discord server](https://discord.gg/NTqfxXsNuN) for discussions, help, and updates

## :gift: Contributing

Please read the [CONTRIBUTING.md](CONTRIBUTING.md) guide.

## 🚧 TODO

- [x] Neovim MCP Server (kind of) with better editing, diffs, terminal integration etc (Ideas are welcome)
- [x] Enhanced help view with comprehensive documentation
- [x] MCP Resources as variables in chat plugins
- [x] MCP Prompts as slash commands in chat plugins
- [x] Enable LLM to start and stop MCP Servers dynamically
- [x] Support SSE transport
- [x] Support /slash_commands in avante
- [x] Support streamable-http transport
- [x] Support OAuth
- [x] Add types
- [x] Better Docs 
- [ ] Add tests
- [ ] Support #variables in avante


## 👏 Acknowledgements

Thanks to:

- [cline/mcp-marketplace](https://github.com/cline/mcp-marketplace) for providing the marketplace api
- [nui.nvim](https://github.com/MunifTanjim/nui.nvim) for inspiring our text highlighting utilities

