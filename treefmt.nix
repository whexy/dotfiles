# treefmt.nix
#
# Single source of truth for formatting. Consumed by:
#   - `nix fmt`                          (flake.formatter)
#   - `checks.<system>.formatting`       (flake check)
#   - the `treefmt` git pre-commit hook  (devShell + checks.<system>.pre-commit)
#
# Formatter choices mirror home/dev/nvim/init.lua so editor and CLI agree.
_: {
  projectRootFile = "flake.nix";
  programs = {
    nixfmt.enable = true; # .nix          (nixfmt-rfc-style)
    prettier.enable = true; # css, html, json, md, yaml
    stylua.enable = true; # .lua
    shfmt.enable = true; # shell scripts
    taplo.enable = true; # .toml
  };
  settings.global.excludes = [
    "*.age"
    "*.jpg"
    "flake.lock"
    "result/*"
  ];
}
