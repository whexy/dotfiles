{ pkgs, ... }:

{
  imports = [
    ./dev.nix
    ./home/personal.nix
  ];

  fonts.packages = [
    (pkgs.nerd-fonts.fira-code)
    (pkgs.nerd-fonts.jetbrains-mono)
  ];

  environment.systemPackages = with pkgs; [
    viu
  ];
}
