# cf, Cloudflare's CLI, signed in with one scoped API token from 1Password
# instead of a `cf auth login` on every host.
#
# cf's wrapper loads the token on each run and exports it to that cf process
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

  # The account that owns the token. The ID authenticates nothing, so it
  # stays in plaintext; replace it if the token moves to another account.
  # Without it, cf picks the token's only account and saves that choice under
  # `.cloudflare/cache/` in whatever directory it ran from.
  accountId = "056856e343cb070b2f297daa073054fa";

  package =
    if cfg.apiToken.enable then
      config.dotfiles.onepassword.wrap {
        package = cf;
        programs = [
          "cf"
          "cloudflare"
        ];
        env.CLOUDFLARE_API_TOKEN = "cloudflare-api-token";
        withSecret.CLOUDFLARE_ACCOUNT_ID = accountId;
        dotenv = true;
        # Shell completion runs `cf complete` on every Tab.
        skipWhen.firstArg = [ "complete" ];
      }
    else
      cf;
in
{
  config = lib.mkIf cfg.cli.enable {
    home.packages = [ package ];
    dotfiles.agents.skills = import ./skills.nix { inherit pkgs perSystem; };
  };
}
