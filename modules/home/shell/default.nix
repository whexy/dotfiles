# Shell group: zsh, nushell, motd.
args@{
  config,
  inputs,
  lib,
  ...
}:
let
  osConfig = args.osConfig or null;
  cfg = config.dotfiles.shell;
  # Integrated homes follow the system shell group, which installs the
  # shells and sets the login shell. Without osConfig, the shell `default`
  # names is on.
  shellEnable =
    name:
    lib.mkOption {
      type = lib.types.bool;
      default = if osConfig != null then osConfig.dotfiles.shell.${name}.enable else cfg.default == name;
      defaultText = lib.literalExpression ''osConfig.dotfiles.shell.${name}.enable, or `default == "${name}"` without osConfig'';
      description = "Whether to enable ${name}.";
    };
in
{
  options.dotfiles.shell = {
    default = lib.mkOption {
      type = lib.types.enum [
        "zsh"
        "nushell"
        "none"
      ];
      default = if osConfig != null then osConfig.dotfiles.shell.default else "zsh";
      defaultText = lib.literalExpression ''osConfig.dotfiles.shell.default, or "zsh" without osConfig'';
      description = "Default user shell. `none` configures no interactive shell, for homes only driven through `/bin/sh -c`.";
    };
    motd = {
      enable = lib.mkEnableOption "system status message of the day (motd)";
    };
    zsh = {
      enable = shellEnable "zsh";
      devExtras = lib.mkEnableOption "shell developer extras (p10k prompt, fzf, zoxide, bat, direnv-instant)";
    };
    nushell = {
      enable = shellEnable "nushell";
      devExtras = lib.mkEnableOption "nushell developer extras (carapace, zoxide, direnv-instant, atuin, starship)";
    };
  };

  imports = [
    inputs.direnv-instant.homeModules.direnv-instant
    ./atuin.nix
    ./motd.nix
    ./tools.nix
    ./zsh.nix
    ./zsh-extras.nix
    ./nushell.nix
    ./nushell-extras.nix
  ];
}
