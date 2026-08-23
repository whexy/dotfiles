# Shell group: zsh and nushell.
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
      ];
      default = defaultShell;
      description = "Default user shell.";
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
    ./zsh.nix
    ./zsh-extras.nix
    ./nushell.nix
    ./nushell-extras.nix
  ];
}
