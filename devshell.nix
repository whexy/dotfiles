{
  inputs,
  flake,
  system,
  perSystem,
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
    # Python packages: interpreter with their dependencies, checker, linter.
    perSystem.self.agent-settings.devPython
    basedpyright
    ruff
  ];
  inherit (preCommit) shellHook;
}
