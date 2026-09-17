# Nix group: user-level nix.conf and the nh CLI helper.
{
  config,
  lib,
  perSystem,
  ...
}:
let
  cfg = config.dotfiles.nix;
  tokenFile = "${config.xdg.configHome}/nix/gh-token.conf";
in
{
  imports = [ ./nh.nix ];

  options.dotfiles.nix = {
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

  config = lib.mkIf cfg.ghTokenFlakes.enable {
    # The activation script refreshes the fragment, so nix.conf itself stays a
    # static file that Home Manager fully owns.
    xdg.configFile."nix/nix.conf".text = ''
      !include ${tokenFile}
    '';

    home = {
      packages = [ perSystem.self.nix-gh-token ];

      # gh reads its token from the keyring, so the value cannot be captured at
      # build time. If the token is later rotated the fragment goes stale and
      # fetches under `scopes` warn and fall back to anonymous access, which
      # only reaches public repos; re-running activation repairs it.
      activation.nixGhToken = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
        run ${perSystem.self.nix-gh-token}/bin/nix-gh-token \
          --out ${lib.escapeShellArg tokenFile} \
          ${lib.escapeShellArgs cfg.ghTokenFlakes.scopes} || true
      '';
    };
  };
}
