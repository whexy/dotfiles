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
  ...
}:
let
  cfg = config.dotfiles.tooling.cloudflare;
  inherit (perSystem.self) cf;

  # Encrypted by hand once (AGENTS.md, "Cloudflare CLI"). Until it exists, cf
  # runs signed out and evaluation warns.
  tokenFile = ../../../secrets/cloudflare-api-token.age;
  withToken = cfg.apiToken.enable && builtins.pathExists tokenFile;

  # The account that owns the token. The ID authenticates nothing, so it
  # stays in plaintext; replace it if the token moves to another account.
  # Without it, cf picks the token's only account and saves that choice under
  # `.cloudflare/cache/` in whatever directory it ran from.
  accountId = "056856e343cb070b2f297daa073054fa";

  # agenix secret paths are shell fragments ("${XDG_RUNTIME_DIR}/agenix/..."
  # on Linux, "$(getconf DARWIN_USER_TEMP_DIR)/agenix/..." on Darwin), so
  # they must stay double-quoted and expand at run time.
  tokenPath = config.age.secrets.cloudflare-api-token.path;

  # -s, not -r: an interrupted decryption leaves an empty file.
  loadToken = ''
    if [ -z "''${CLOUDFLARE_API_TOKEN:-}" ] &&
      ! ${lib.getExe pkgs.gnugrep} -Eqs '^[[:space:]]*(export[[:space:]]+)?CLOUDFLARE_API_TOKEN[[:space:]]*=' .env; then
      if [ -s "${tokenPath}" ]; then
        CLOUDFLARE_API_TOKEN=$(<"${tokenPath}")
        export CLOUDFLARE_API_TOKEN
        export CLOUDFLARE_ACCOUNT_ID="''${CLOUDFLARE_ACCOUNT_ID:-${accountId}}"
      else
        echo "cf: no Cloudflare API token at ${tokenPath}; running signed out" >&2
      fi
    fi
  '';

  package =
    if withToken then
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
  config = lib.mkIf cfg.cli.enable (
    lib.mkMerge [
      { home.packages = [ package ]; }

      (lib.mkIf withToken {
        age.secrets.cloudflare-api-token.file = tokenFile;
      })

      (lib.mkIf (cfg.apiToken.enable && !withToken) {
        warnings = [
          ''
            dotfiles.tooling.cloudflare.apiToken.enable is set, but
            secrets/cloudflare-api-token.age does not exist yet, so cf runs
            signed out. Provision it as AGENTS.md describes under
            "Cloudflare CLI".
          ''
        ];
      })
    ]
  );
}
