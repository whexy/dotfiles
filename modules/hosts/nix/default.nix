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
      nix.settings = import ../../../lib/nix-settings.nix;
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
