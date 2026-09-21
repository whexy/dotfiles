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
in
{
  imports = [ ./nh.nix ];

  options.dotfiles.nix = {
    caches.enable = lib.mkEnableOption "shared Nix client settings and binary caches (cache overrides require daemon trust)";
    pinRegistry.enable = lib.mkEnableOption "pinning the user nixpkgs registry and search path";

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
      nix.settings = import ../../../lib/nix-settings.nix;
    })
    (lib.mkIf cfg.pinRegistry.enable {
      nix.registry.nixpkgs.flake = inputs.nixpkgs;
      nix.nixPath = lib.mkBefore [ "nixpkgs=${inputs.nixpkgs}" ];
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
