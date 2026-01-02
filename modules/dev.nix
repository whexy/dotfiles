# Development environment (for remote dev hosts)
{ pkgs, ... }:

{
  imports = [
    ./base.nix
    ./home/dev.nix
  ];

  environment.systemPackages = with pkgs; [
    age
    cmake
    fd
    gcc
    gdb
    kubectl
    llvm
    mtr
    nodejs
    ripgrep
    rustup
    tldr
    typst
    zellij
  ];

  nixpkgs.overlays = [
    (import ./overlays/mk-op-wrapped.nix)
  ];

  home-manager.useGlobalPkgs = true;
}
