{
  description = "A powerful Neovim plugin for managing MCP (Model Context Protocol) servers";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";

    flake-parts.url = "github:hercules-ci/flake-parts";
    flake-parts.inputs.nixpkgs-lib.follows = "nixpkgs";
  };

  outputs = inputs @ { self, flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];

      perSystem = { pkgs, ... }: {
        packages.default = pkgs.vimUtils.buildVimPlugin {
          pname = "mcphub.nvim";
          version = toString (self.shortRev or self.dirtyShortRev or self.lastModified or "unknown");
          src = self;
          dependencies = [ pkgs.vimPlugins.plenary-nvim ];
          nvimSkipModule = [
            "bundled_build"
            "mcphub.extensions.avante"
            "mcphub.extensions.codecompanion"
            "mcphub.extensions.codecompanion.xml_tool"
            "mcphub.extensions.lualine"
          ];
        };
      };
    };
}

