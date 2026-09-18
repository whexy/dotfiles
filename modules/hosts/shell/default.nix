# Shell group: system shells.
{ config, lib, ... }:
let
  cfg = config.dotfiles.shell;
in
{
  options.dotfiles.shell = {
    default = lib.mkOption {
      type = lib.types.enum [
        "zsh"
        "nushell"
      ];
      default = "zsh";
      description = "Default login shell for the primary user.";
    };
    zsh.enable = lib.mkEnableOption "zsh as a system shell";
    nushell.enable = lib.mkEnableOption "nushell as a system shell";
  };

  config = {
    dotfiles.shell = {
      zsh.enable = lib.mkIf (cfg.default == "zsh") (lib.mkDefault true);
      nushell.enable = lib.mkIf (cfg.default == "nushell") (lib.mkDefault true);
    };
  };
}
