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
    (lib.mkIf cfg.zsh.enable {
      programs.zsh.enable = true;
    })
    (lib.mkIf (cfg.zsh.enable || cfg.nushell.enable) {
      environment.shells =
        with pkgs;
        [ bash ] ++ lib.optional cfg.zsh.enable zsh ++ lib.optional cfg.nushell.enable nushell;
    })
    (lib.mkIf cfg.nushell.enable {
      environment.systemPackages = [ pkgs.nushell ];
    })
  ];
}
