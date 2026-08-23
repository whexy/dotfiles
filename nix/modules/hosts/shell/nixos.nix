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
  config = lib.mkMerge [
    (lib.mkIf cfg.zsh.enable { programs.zsh.enable = true; })
    (lib.mkIf cfg.nushell.enable {
      environment.shells = [ pkgs.nushell ];
    })
  ];
}
