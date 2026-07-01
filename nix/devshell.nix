{
  inputs,
  flake,
  pkgs,
  system,
  ...
}:
let
  treefmtEval = inputs.treefmt-nix.lib.evalModule pkgs ./treefmt.nix;
  preCommit = inputs.git-hooks.lib.${system}.run {
    src = flake;
    hooks = {
      treefmt = {
        enable = true;
        package = treefmtEval.config.build.wrapper;
      };
      statix.enable = true;
      nil.enable = true;
      deadnix.enable = true;
    };
  };
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
