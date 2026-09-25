# Shell group: zsh, nushell, motd.
args@{
  config,
  lib,
  ...
}:
let
  osConfig = args.osConfig or null;
  cfg = config.dotfiles.shell;
  defaultShell = if osConfig != null then (osConfig.dotfiles.shell.default or "zsh") else "zsh";
in
{
  options.dotfiles.shell = {
    default = lib.mkOption {
      type = lib.types.enum [
        "zsh"
        "nushell"
        "none"
      ];
      default = defaultShell;
      description = "Default user shell. `none` configures no interactive shell, for homes only driven through `/bin/sh -c`.";
    };
    motd = {
      enable = lib.mkEnableOption "system status message of the day (motd)";
    };
    zsh = {
      enable = lib.mkEnableOption "zsh";
      devExtras = lib.mkEnableOption "shell developer extras (p10k prompt, fzf, zoxide, bat, direnv)";
    };
    nushell = {
      enable = lib.mkEnableOption "nushell";
      devExtras = lib.mkEnableOption "nushell developer extras (carapace, zoxide, direnv, atuin, starship)";
    };
  };

  config = {
    dotfiles.shell = {
      zsh.enable = lib.mkIf (cfg.default == "zsh") (lib.mkDefault true);
      nushell.enable = lib.mkIf (cfg.default == "nushell") (lib.mkDefault true);
    };
  };

  imports = [
    ./atuin.nix
    ./motd.nix
    ./zsh.nix
    ./zsh-extras.nix
    ./nushell.nix
    ./nushell-extras.nix
  ];
}
