# Extra dev utilities: heavier or less frequently used tools.
{
  config,
  pkgs,
  lib,
  ...
}:
{
  config = lib.mkIf config.dotfiles.tooling.extras.enable {
    home.packages = with pkgs; [
      devenv
      magic-wormhole-rs
      qemu
      sqlite
      watchexec
      woodpecker-cli
      xh
      yazi
      yq
    ];
  };
}
