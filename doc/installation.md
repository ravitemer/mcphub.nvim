# Installation

Please read the [getting started](/index) guide before reading this.

## Requirements

- Neovim >= 0.8.0 (built with LuaJIT)
- Node.js >= 18.0.0
- [plenary.nvim](https://github.com/nvim-lua/plenary.nvim)
- [mcp-hub](https://github.com/ravitemer/mcp-hub) (automatically installed via build command)
- [jq](https://github.com/jqlang/jq) (optional, for better servers.json formatting)

## Lazy.nvim

MCPHub.nvim requires [mcp-hub](https://github.com/ravitemer/mcp-hub) to manage MCP Servers. You can make `mcp-hub` binary available in three ways:

1. [Global Installation](#default-installation) (Recommended)
2. [Local Installation](#local-installation)
3. [Dev Installation](#dev-installation)

### Default Installation

Install `mcp-hub` node binary globally using `npm`, `yarn`, or `bun` any other node package manager using the `build` command. The `build` command will run everytime the plugin is updated.

```lua
{
    "ravitemer/mcphub.nvim",
    dependencies = {
        "nvim-lua/plenary.nvim",
    },
    build = "npm install -g mcp-hub@latest",  -- Installs `mcp-hub` node binary globally
    config = function()
        require("mcphub").setup()
    end
}
```

Please see [configuration](/configuration) for default plugin config and on how to configure the plugin.

### Local Installation

Ideal for environments where global binary installations aren't possible.

Download `mcp-hub` binary alongside the neovim plugin using `bundled_build.lua` for the `build` command. We need to explicitly set `use_bundled_binary` to `true` to let the plugin use the locally available `mcp-hub` binary.

```lua
{
    "ravitemer/mcphub.nvim",
    dependencies = {
        "nvim-lua/plenary.nvim",
    },
    build = "bundled_build.lua",  -- Bundles `mcp-hub` binary along with the neovim plugin
    config = function()
        require("mcphub").setup({
            use_bundled_binary = true,  -- Use local `mcp-hub` binary
        })
    end,
}
```

### Dev Installation

Ideal for development. You can provide the command that our plugin should use to start the `mcp-hub` server. You can clone the `mcp-hub` repo locally using `gh clone ravitemer/mcp-hub` and provide the path to the `cli.js` as shown below:

```lua
{
    "ravitemer/mcphub.nvim",
    dependencies = {
        "nvim-lua/plenary.nvim",
    },
    config = function()
        require("mcphub").setup({
            cmd = "node",
            cmdArgs = {"/path/to/mcp-hub/src/utils/cli.js"},
        })
    end,
}
```

See [Contributing](https://github.com/ravitemer/mcphub.nvim/blob/main/CONTRIBUTING.md) guide for detailed development setup.

## NixOS

<details>
<summary> Flake install</summary>

Just add it to your NixOS flake.nix or home-manager:

```nix
inputs = {
mcphub-nvim.url = "github:ravitemer/mcphub.nvim";
...
}
```

To integrate mcphub.nvim to your NixOS/Home Manager nvim configs, add the following to your [neovim.plugins](https://nixos.wiki/wiki/Neovim#Installing_Plugins) or your [neovim.packages](https://nixos.wiki/wiki/Neovim#System-wide_2)

```nix
inputs.mcphub-nvim.packages."${system}".default
```

and add the setup function in [lua code](https://nixos.wiki/wiki/Neovim#Note_on_Lua_plugins)

### Nixvim example

[Nixvim](https://github.com/nix-community/nixvim) example:

```nix
{ mcphub-nvim, ... }:
{
extraPlugins = [mcphub-nvim];
extraConfigLua = ''
require("mcphub").setup()
'';
}

# where
{
# For nixpkgs (not available yet)
# ...

# For flakes
mcphub-nvim = inputs.mcphub-nvim.packages."${system}".default;
}
```

</details>

<details>
<summary>Nixpkgs install</summary>

> coming...

</details>
