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
  ...
}:
let
  cfg = config.dotfiles.tooling.woodpecker;

  # agenix secret paths are shell fragments ("${XDG_RUNTIME_DIR}/agenix/..."
  # on Linux, "$(getconf DARWIN_USER_TEMP_DIR)/agenix/..." on Darwin), so
  # they must reach the script double-quoted and be expanded at runtime.
  tokenPath = "\"${config.age.secrets.woodpecker-token.path}\"";

  wrapped = pkgs.writeShellScriptBin "woodpecker-cli" ''
    set -euo pipefail

    # -s, not -r: an interrupted agenix decryption leaves a readable but
    # empty file, and an empty token surfaces as a confusing 401 from the
    # server instead of a local secret problem.
    if [ ! -s ${tokenPath} ]; then
      echo "woodpecker-cli: missing token secret: ${config.age.secrets.woodpecker-token.path}" >&2
      exit 1
    fi

    export WOODPECKER_SERVER=${lib.escapeShellArg cfg.server}
    WOODPECKER_TOKEN="$(cat ${tokenPath})"
    export WOODPECKER_TOKEN
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
