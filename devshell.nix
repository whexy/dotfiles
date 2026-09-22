{
  inputs,
  flake,
  system,
  ...
}:
let
  inherit (import ./lib/dev-tools.nix { inherit inputs flake; } system) pkgs preCommit;
in
pkgs.mkShell {
  packages = with pkgs; [
    just
    nixfmt
    statix
    nil
    nixd
    deadnix
    stylua
    prettier
    shfmt
    taplo
  ];
  inherit (preCommit) shellHook;
}
