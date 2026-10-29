# Nix group: package manager settings (caches, garbage collection,
# optimisation, builder VM).
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
    ciCache.enable = lib.mkOption {
      type = lib.types.bool;
      default = config.dotfiles.network.tailscale.enable;
      defaultText = lib.literalExpression "config.dotfiles.network.tailscale.enable";
      example = false;
      description = ''
        Whether the Nix daemon substitutes, for every user, from whexy/ci-cache's
        cache of CI builds. It follows Tailscale because the cache is served
        only on the tailnet.
      '';
    };
    rexNetrc.enable = lib.mkEnableOption ''
      Rex's testing token in Nix's netrc, which fetching this flake's `rex`
      input needs until Rex's first release
    '';
    pinRegistry.enable = lib.mkEnableOption "pinning the `nixpkgs` flake reference to this system's nixpkgs";
    gc.enable = lib.mkEnableOption "weekly garbage collection of system profile generations older than 14 days";
    optimise.enable = lib.mkEnableOption "automatic nix store optimisation";
    linuxBuilder.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      example = true;
      description = ''
        Whether to enable the nix-darwin Linux builder VM (build NixOS
        configurations on macOS). It does not start at boot; start and stop
        it with:

            sudo launchctl kickstart system/org.nixos.linux-builder
            sudo launchctl kill SIGTERM system/org.nixos.linux-builder

        While it is stopped or still booting, Nix cannot reach it and fails
        any Linux derivation that no binary cache provides.
      '';
    };
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.caches.enable {
      # nixpkgs.config.allowUnfree is set at the blueprint level in flake.nix;
      # setting it here would trip the "nixpkgs.config with nixpkgs.pkgs" assertion
      # since blueprint injects nixpkgs.pkgs into every host.
      nix.settings = import ../../../lib/nix-settings.nix;
    })

    (lib.mkIf cfg.ciCache.enable {
      nix.settings = import ../../../lib/ci-cache-settings.nix;
    })

    (lib.mkIf cfg.rexNetrc.enable {
      # Nix fetches flake inputs in the evaluating process, so the netrc must
      # be readable by the primary user's evaluations as well as root's.
      age.secrets.rex-package-netrc = {
        file = ../../../secrets/rex-package-netrc.age;
        owner = config.dotfiles.host.username;
      };
      nix.settings.netrc-file = config.age.secrets.rex-package-netrc.path;
    })

    (lib.mkIf cfg.pinRegistry.enable {
      nix = {
        # `nix run nixpkgs#pkg` would otherwise re-resolve a branch head on
        # every call under tarball-ttl = 0. Pinning also makes ad-hoc commands
        # use the same package set as the system closure, unfree included.
        registry.nixpkgs.to = {
          type = "path";
          path = "${pkgs.callPackage ../../../lib/unfree-nixpkgs.nix { nixpkgs = systemNixpkgs; }}";
        };

        # Deliberately unpinned: `nix shell unstable#pkg` reaches packages
        # newer than the stable system branch.
        registry.unstable.to = {
          type = "github";
          owner = "NixOS";
          repo = "nixpkgs";
          ref = "nixpkgs-unstable";
        };

        # Takes precedence over the channel entry so `<nixpkgs>` agrees with
        # the registry.
        nixPath = lib.mkBefore [ "nixpkgs=${systemNixpkgs}" ];
      };
    })

    (lib.mkIf cfg.gc.enable {
      nix.gc = {
        automatic = true;
        options = "--delete-older-than 14d";
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
