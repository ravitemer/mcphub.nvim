{
  description = "A Neovim plugin for Minecraft mod development assistance";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";

    flake-parts.url = "github:hercules-ci/flake-parts";
    flake-parts.inputs.nixpkgs-lib.follows = "nixpkgs";
  };

  outputs = inputs @ { self, flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];

      perSystem = { system, ... }: let
        pkgs = inputs.nixpkgs.legacyPackages.${system};
      in {
        packages.default = pkgs.vimUtils.buildVimPlugin {
          name = "mcphub.nvim";
          src = self;
          nvimSkipModule = [
            "mcphub"
            "mcphub.hub"
            "mcphub.extensions.codecompanion"
            "bundled_build"
            "mcphub.extensions.lualine"
            "mcphub.native.neovim.lsp"
            "mcphub.native.neovim.terminal"
            "mcphub.native.neovim.files.search"
            "mcphub.native.neovim.files.write"
            "mcphub.native.neovim.files.operations"
            "mcphub.native.neovim.files.init"
            "mcphub.native.neovim.files.replace"
            "mcphub.native.neovim.init"
            "mcphub.native.neovim.prompts"
            "mcphub.native.mcphub.init"
            "mcphub.native.mcphub.guide"
            "mcphub.extensions.codecompanion.xml_tool"
          ];
        };
      };
    };
}

