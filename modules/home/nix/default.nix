# Nix group: user-level nix.conf and the nh CLI helper.
{
  config,
  lib,
  perSystem,
  pkgs,
  inputs,
  ...
}:
let
  cfg = config.dotfiles.nix;
  tokenFile = "${config.xdg.configHome}/nix/gh-token.conf";
  gcArgs = [
    "--delete-older-than"
    "30d"
  ];
in
{
  imports = [ ./nh.nix ];

  options.dotfiles.nix = {
    caches = {
      enable = lib.mkEnableOption "shared Nix client settings and binary caches (cache overrides require daemon trust)";

      acceptFlakeConfig = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Whether flakes may set their own `nixConfig` without asking.

          Where the user owns the store (no daemon), an accepted flake can add
          substituters and trusted keys or a `post-build-hook` for every later
          build, so homes running untrusted code turn this off.
        '';
      };
    };
    pinRegistry.enable = lib.mkEnableOption "pinning the user nixpkgs registry and search path";
    gc.enable = lib.mkEnableOption "weekly garbage collection of this user's profile generations older than 30 days";

    ghTokenFlakes = {
      enable = lib.mkEnableOption "using the gh CLI token for private `github:` flake fetches";

      scopes = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ "github.com/whexy" ];
        example = [
          "github.com/whexy"
          "github.com/some-org"
        ];
        description = ''
          Owner-scoped `access-tokens` keys the gh token is bound to.

          Scoping to owners rather than to `github.com` is a safety property,
          not a preference: a stale token attached to bare `github.com` makes
          every public flake fetch fail with HTTP 401.
        '';
      };
    };
  };

  config = lib.mkMerge [
    (lib.mkIf (cfg.caches.enable || cfg.ghTokenFlakes.enable) {
      # Home Manager uses this package to validate nix.conf, not to manage the daemon.
      nix.package = lib.mkDefault pkgs.nix;
    })
    (lib.mkIf cfg.caches.enable {
      nix.settings = import ../../../lib/nix-settings.nix // {
        accept-flake-config = cfg.caches.acceptFlakeConfig;
      };
    })
    (lib.mkIf cfg.pinRegistry.enable {
      nix = {
        registry.nixpkgs.flake = inputs.nixpkgs;
        # Deliberately unpinned: `nix shell unstable#pkg` reaches packages
        # newer than the stable branch.
        registry.unstable.to = {
          type = "github";
          owner = "NixOS";
          repo = "nixpkgs";
          ref = "nixpkgs-unstable";
        };
        nixPath = lib.mkBefore [ "nixpkgs=${inputs.nixpkgs}" ];
      };
    })
    # The system collector runs as root and never reaches profiles under this
    # user's XDG state directory, so integrated homes need this one too.
    (lib.mkIf cfg.gc.enable {
      nix.gc = {
        automatic = true;
        dates = "weekly";
        randomizedDelaySec = "2h";
        options = lib.escapeShellArgs gcArgs;
      };

      # Home Manager's agent passes `options` as a single argument, which
      # nix-collect-garbage rejects as an unrecognised flag.
      launchd.agents.nix-gc.config.ProgramArguments = lib.mkForce (
        [ (lib.getExe' (lib.defaultTo pkgs.nix config.nix.package) "nix-collect-garbage") ] ++ gcArgs
      );
    })
    (lib.mkIf cfg.ghTokenFlakes.enable {
      nix.extraOptions = ''
        !include ${tokenFile}
      '';

      home = {
        packages = [ perSystem.self.nix-gh-token ];

        # gh reads its token from the keyring, so the value cannot be captured at
        # build time. If the token is later rotated the fragment goes stale and
        # every fetch under `scopes` fails with HTTP 401 until activation runs
        # again, which validates the token and drops the fragment.
        activation.nixGhToken = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
          run ${perSystem.self.nix-gh-token}/bin/nix-gh-token \
            --out ${lib.escapeShellArg tokenFile} \
            ${lib.escapeShellArgs cfg.ghTokenFlakes.scopes} || true
        '';
      };
    })
  ];
}
