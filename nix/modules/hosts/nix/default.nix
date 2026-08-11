# Nix group: package manager settings (caches, optimisation, builder VM).
{ config, lib, ... }:
let
  cfg = config.dotfiles.nix;
in
{
  options.dotfiles.nix = {
    caches.enable = lib.mkEnableOption "dotfiles binary caches and flake settings";
    optimise.enable = lib.mkEnableOption "automatic nix store optimisation";
    linuxBuilder.enable = lib.mkEnableOption "the nix-darwin Linux builder VM (build NixOS configurations on macOS)";
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.caches.enable {
      # nixpkgs.config.allowUnfree is set at the blueprint level in flake.nix;
      # setting it here would trip the "nixpkgs.config with nixpkgs.pkgs" assertion
      # since blueprint injects nixpkgs.pkgs into every host.
      nix.settings = {
        extra-substituters = [
          "https://cache.numtide.com"
          "https://nix-community.cachix.org"
          "https://niri.cachix.org"
          "https://whexy.cachix.org"
        ];
        extra-trusted-public-keys = [
          "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
          "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
          "niri.cachix.org-1:Wv0OmO7PsuocRKzfDoJ3mulSl7Z6oezYhGhR+3W2964="
          "whexy.cachix.org-1:XzmCWs+qh3vMtB4p1joLM+ajn5z/UYgZOyxykzEDV2o="
        ];
        experimental-features = [
          "nix-command"
          "flakes"
        ];
        warn-dirty = false;
      };
    })

    (lib.mkIf cfg.optimise.enable {
      nix = {
        optimise.automatic = true;
        settings.auto-optimise-store = true;
      };
    })
  ];
}
