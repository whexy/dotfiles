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
      };
    };
  };
}
