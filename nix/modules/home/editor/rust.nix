# Rust: toolchain manager (rustup provides rust-analyzer and rustfmt).
{
  config,
  pkgs,
  lib,
  ...
}:
{
  config = lib.mkIf config.dotfiles.editor.rust.enable {
    home.packages = with pkgs; [
      rustup
    ];
  };
}
