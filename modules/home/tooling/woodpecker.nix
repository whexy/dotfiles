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

  wrapped = config.dotfiles.onepassword.wrap {
    package = pkgs.woodpecker-cli;
    env.WOODPECKER_TOKEN = "woodpecker-token";
    # Shell completion runs woodpecker-cli with this flag on every Tab. It
    # contacts no server, but will not start without a token.
    skipWhen = {
      anyArg = [ "--generate-shell-completion" ];
      env.WOODPECKER_TOKEN = "completion";
    };
    wrapperArgs = [
      # A default, so a caller's token for another server never goes here.
      "--set-default"
      "WOODPECKER_SERVER"
      cfg.server
      # Nix owns this binary; the self-updater must never fire.
      "--set"
      "WOODPECKER_DISABLE_UPDATE_CHECK"
      "1"
    ];
  };
in
{
  config = lib.mkIf cfg.enable {
    home.packages = [ wrapped ];
  };
}
