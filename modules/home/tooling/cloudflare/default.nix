# cf, Cloudflare's CLI, signed in with one scoped API token from agenix
# instead of a `cf auth login` on every host.
#
# cf's wrapper reads the token on each run and exports it to that cf process
# alone (and what it starts, such as a project's build), so no shell or agent
# environment holds it. A token the caller brings wins: one already in the
# environment, or one in the `.env` cf reads from the current directory,
# which an exported token would otherwise override.
{
  config,
  lib,
  pkgs,
  perSystem,
  flake,
  ...
}:
let
  cfg = config.dotfiles.tooling.cloudflare;
  inherit (perSystem.self) cf;

  # The account that owns the token. The ID authenticates nothing, so it
  # stays in plaintext; replace it if the token moves to another account.
  # Without it, cf picks the token's only account and saves that choice under
  # `.cloudflare/cache/` in whatever directory it ran from.
  accountId = "056856e343cb070b2f297daa073054fa";

  loadToken = flake.lib.secretEnv.export {
    name = "cf";
    variable = "CLOUDFLARE_API_TOKEN";
    path = config.age.secrets.cloudflare-api-token.path;
    required = false;
    callerHas = ''
      [ -n "''${CLOUDFLARE_API_TOKEN:-}" ] ||
        ${lib.getExe pkgs.gnugrep} -Eqs '^[[:space:]]*(export[[:space:]]+)?CLOUDFLARE_API_TOKEN[[:space:]]*=' .env
    '';
    onLoad = ''export CLOUDFLARE_ACCOUNT_ID="''${CLOUDFLARE_ACCOUNT_ID:-${accountId}}"'';
  };

  package =
    if cfg.apiToken.enable then
      pkgs.symlinkJoin {
        inherit (cf) name meta;
        paths = [ cf ];
        nativeBuildInputs = [ pkgs.makeWrapper ];
        postBuild = ''
          for program in cf cloudflare; do
            wrapProgram $out/bin/$program --run ${lib.escapeShellArg loadToken}
          done
        '';
      }
    else
      cf;
in
{
  config = lib.mkIf cfg.cli.enable {
    home.packages = [ package ];
    dotfiles.agents.skills = import ./skills.nix { inherit pkgs perSystem; };
    age.secrets.cloudflare-api-token = lib.mkIf cfg.apiToken.enable {
      file = ../../../../secrets/cloudflare-api-token.age;
    };
  };
}
