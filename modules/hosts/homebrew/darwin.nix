# Homebrew Darwin configuration: the Homebrew machinery itself.
# Casks are contributed by the semantic feature groups (browser, security,
# streaming, desktop), each gated by its own functionality option.
{ config, lib, ... }:
let
  cfg = config.dotfiles.homebrew;
in
{
  config = lib.mkIf cfg.enable {
    homebrew = {
      enable = true;
      onActivation = {
        autoUpdate = true;
        upgrade = true;
        cleanup = "zap";
        # Homebrew 5.1+ requires explicit confirmation for `brew bundle --cleanup`.
        extraFlags = [ "--force" ];
        # Self-updating casks are left to their own updaters. Homebrew's
        # upgrade of them can need sudo (pkg installers, uninstall steps under
        # /Library), which the unattended auto-upgrade cannot answer, and a
        # failed `brew bundle` aborts the rest of activation.
        extraEnv.HOMEBREW_NO_UPGRADE_AUTO_UPDATES_CASKS = "1";
      };
    };
  };
}
