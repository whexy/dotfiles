{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.dotfiles.shell;
in
{
  # Required at system level so zsh can be used as a user shell.
  config = lib.mkIf cfg.zsh.enable {
    programs.zsh.enable = true;
    environment.shells = with pkgs; [
      bash
      zsh
    ];
  };
}
