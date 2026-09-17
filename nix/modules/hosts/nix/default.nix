# Nix group: package manager settings (caches, optimisation, builder VM).
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
let
  cfg = config.dotfiles.nix;

  # Darwin hosts build against the nixpkgs-darwin branch, so their registry
  # entry has to follow the same input the host's pkgs came from.
  systemNixpkgs = if pkgs.stdenv.hostPlatform.isDarwin then inputs.nixpkgs-darwin else inputs.nixpkgs;
in
{
  options.dotfiles.nix = {
    caches.enable = lib.mkEnableOption "dotfiles binary caches and flake settings";
    pinRegistry.enable = lib.mkEnableOption "pinning the `nixpkgs` flake reference to this system's nixpkgs";
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
        accept-flake-config = true;
        warn-dirty = false;

        # Never serve an unlocked ref like `github:whexy/x` from the fetcher
        # cache: anything worth fetching unlocked is worth fetching fresh.
        # Locked flake inputs are content-addressed and unaffected.
        tarball-ttl = 0;
      };
    })

    (lib.mkIf cfg.pinRegistry.enable {
      nix = {
        # `nix run nixpkgs#pkg` would otherwise re-resolve a branch head on
        # every call under tarball-ttl = 0. Pinning also makes ad-hoc commands
        # use the same package set as the system closure.
        registry.nixpkgs.flake = systemNixpkgs;

        # Takes precedence over the channel entry so `<nixpkgs>` agrees with
        # the registry.
        nixPath = lib.mkBefore [ "nixpkgs=${systemNixpkgs}" ];
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
