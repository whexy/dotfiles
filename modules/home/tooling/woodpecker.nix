# woodpecker-cli preconfigured against my server.
#
# `woodpecker-cli setup` writes server_url into XDG config and pushes the
# token into the OS keyring; neither is declarable, so a fresh host would
# need an interactive setup. WOODPECKER_SERVER/WOODPECKER_TOKEN take
# precedence over both, so this wrapper replaces setup everywhere.
{
  config,
  pkgs,
  lib,
  flake,
  ...
}:
let
  cfg = config.dotfiles.tooling.woodpecker;

  wrapped = pkgs.writeShellScriptBin "woodpecker-cli" ''
    set -euo pipefail

    # An empty token would surface as a confusing 401 from the server
    # instead of a local secret problem.
    ${flake.lib.secretEnv.export {
      name = "woodpecker-cli";
      variable = "WOODPECKER_TOKEN";
      path = config.age.secrets.woodpecker-token.path;
      required = true;
    }}
    export WOODPECKER_SERVER=${lib.escapeShellArg cfg.server}
    # Nix owns this binary; the self-updater must never fire.
    export WOODPECKER_DISABLE_UPDATE_CHECK=1

    exec ${lib.getExe pkgs.woodpecker-cli} "$@"
  '';
in
{
  config = lib.mkIf cfg.enable {
    home.packages = [ wrapped ];

    age.secrets.woodpecker-token.file = ../../../secrets/woodpecker-token.age;
  };
}
