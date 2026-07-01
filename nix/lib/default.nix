{ inputs, flake, ... }:
let
  overlays = {
    container-darwin = import ../overlays/container-darwin.nix;
    direnv-darwin = import ../overlays/direnv-darwin.nix;
    lkl-bigmem = import ../overlays/lkl-bigmem.nix;
    op-wsl = import ../overlays/op-wsl.nix;
    ssh-wsl = import ../overlays/ssh-wsl.nix;
    unstable = import ../overlays/unstable.nix { inherit (inputs) nixpkgs-unstable; };
    llm-tools = import ../overlays/llm-tools.nix { inherit (inputs) llm-agents; };
  };
in
{
  inherit overlays;

  mkStandaloneHome =
    {
      system,
      modules,
      overlays ? [ ],
    }:
    let
      pkgs = import inputs.nixpkgs {
        inherit system overlays;
        config.allowUnfree = true;
      };
    in
    inputs.home-manager.lib.homeManagerConfiguration {
      inherit pkgs modules;
      extraSpecialArgs = {
        inherit inputs flake;
        darwin = false;
        wsl = false;
      };
    };
}
