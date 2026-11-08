# Terminal group: emulators and multiplexers.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.dotfiles.terminal;
in
{
  options.dotfiles.terminal = {
    ghostty = {
      enable = lib.mkEnableOption "the Ghostty terminal emulator";
      package = lib.mkOption {
        type = lib.types.package;
        # nixpkgs builds Ghostty from source only for Linux; on macOS it
        # repackages the upstream app.
        default = if pkgs.stdenv.hostPlatform.isDarwin then pkgs.ghostty-bin else pkgs.ghostty;
        defaultText = lib.literalExpression "if isDarwin then pkgs.ghostty-bin else pkgs.ghostty";
        description = "Ghostty package, whose terminfo and shell integration other modules use too.";
      };
      terminfo.enable = lib.mkEnableOption "Ghostty's xterm-ghostty terminfo entry, for Ghostty terminals that reach this machine";
    };
    tmux.enable = lib.mkEnableOption "tmux";
    zellij.enable = lib.mkEnableOption "zellij";
    rex = {
      enable = lib.mkEnableOption "the Rex Beta terminal multiplexer app with Ghostty's look (macOS)";
      terminfo.enable = lib.mkEnableOption "Rex's xterm-rex terminfo entry, for Rex terminals that reach this machine";
    };
    adopt.enable = lib.mkEnableOption "totmux/tozellij job adoption wrappers (Linux)";
  };

  imports = [
    ./adopt.nix
    ./ghostty.nix
    ./rex.nix
    ./tmux.nix
    ./zellij.nix
  ];

  config = lib.mkIf cfg.ghostty.terminfo.enable {
    home.packages = [ cfg.ghostty.package.terminfo ];
  };
}
