# agent home cap preset: a workspace for an autonomous agent that drives the
# machine from outside, one shell command at a time. Git, toolchains, search,
# build, test and debug tools; no interactive apps, personal identity, SSH,
# agent harnesses, or secrets.
#
# Used instead of base, not on top of it, since base carries a person's
# terminal. Assigns dotfiles.* home options (plain priority); users and hosts
# can override individual options with lib.mkForce.
{ pkgs, lib, ... }:
{
  dotfiles = {
    nix = {
      caches = {
        enable = lib.mkDefault true;
        acceptFlakeConfig = lib.mkDefault false;
      };
      # Resolves `nixpkgs#…` to the revision the home was built from, so
      # most tools an agent asks for are already in the store.
      pinRegistry.enable = lib.mkDefault true;
    };
    shell.default = lib.mkDefault "none";
    vcs.git = {
      enable = lib.mkDefault true;
      identity = {
        name = lib.mkDefault "Sandbox Agent";
        email = lib.mkDefault "agent@sandbox.invalid";
      };
      signing.enable = lib.mkDefault false;
    };
  };

  # `nix-locate` answers "which package provides this command" for
  # `nix shell`. comma is left out: it needs a terminal to pick a package.
  programs.nix-index.enable = lib.mkDefault true;

  home = {
    stateVersion = "26.05";

    packages = with pkgs; [
      # Search and edit
      ripgrep
      fd
      ast-grep
      sd
      jq
      yq-go
      tree
      file
      gnupatch

      # Archives and transfer
      curl
      wget
      rsync
      unzip
      zip
      p7zip
      zstd

      # Build and test
      gcc
      gnumake
      cmake
      pkg-config
      just
      python3
      uv
      nodejs
      pnpm
      unstable.typescript
      sqlite

      # Debug
      strace
      ltrace
      lsof
      gdb
      dig
    ];
  };
}
