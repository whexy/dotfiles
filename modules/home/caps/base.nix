# base home cap preset: terminal essentials every user gets.
#
# Assigns dotfiles.* home options with lib.mkDefault; users and hosts can
# override individual options with plain assignments.
args@{
  pkgs,
  lib,
  inputs,
  ...
}:
let
  osConfig = args.osConfig or null;
  p = pkgs.unstable;
  witr-pkg = p.witr;
in
{
  dotfiles = {
    nix = {
      nh.enable = lib.mkDefault true;
      caches.enable = lib.mkDefault (osConfig == null);
      pinRegistry.enable = lib.mkDefault (osConfig == null);
      gc.enable = lib.mkDefault true;
    };
    monitors.htop.enable = lib.mkDefault true;
    monitors.btop.enable = lib.mkDefault true;
    terminal = {
      tmux.enable = lib.mkDefault true;
      ghostty.terminfo.enable = lib.mkDefault true;
      rex.terminfo.enable = lib.mkDefault true;
    };
    ssh.client.enable = lib.mkDefault true;
    vcs.git.command.enable = lib.mkDefault true;
    shell.motd.enable = lib.mkDefault true;
    editor.neovim.enable = lib.mkDefault true;
  };

  home = {
    packages =
      with pkgs;
      [
        witr-pkg
        curl
        inputs.home-manager.packages.${pkgs.stdenv.hostPlatform.system}.home-manager
        jq
        magic-wormhole-rs
        mosh
        podman
        rsync
        wget
        unzip
        zstd
        # Not in the stable branch yet.
        p.tailcat
      ]
      # macOS ships the BSD userland, which lacks GNU tools like `timeout`.
      ++ lib.optionals pkgs.stdenv.hostPlatform.isDarwin [ coreutils ];
  };
}
