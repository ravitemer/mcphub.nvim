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
            "mcphub.hub"
            "mcphub.extensions.codecompanion"
            "mcphub"
          ];
        };
      };
    };
}

