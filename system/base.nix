{ ... }:
{
  imports = [ ../overlays/nixpkgs-settings.nix ];

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];
}
