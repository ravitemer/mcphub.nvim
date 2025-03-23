{
  description = "A Neovim plugin for Minecraft mod development assistance";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      supportedSystems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
    in
    {
      packages = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = pkgs.vimUtils.buildVimPlugin {
            name = "mcphub.nvim";
            src = self;
            nvimSkipModule = [
              "mcphub.hub"
              "mcphub.extensions.codecompanion"
              "mcphub"
            ];
          };
        });
    };
}

