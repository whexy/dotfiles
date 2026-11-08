{ pkgs }:
let
  inherit (pkgs) lib;
in
pkgs.buildGoModule {
  pname = "dotfiles-upgraded";
  version = "0.1.0";
  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./go.mod
      (lib.fileset.fileFilter (file: file.hasExt "go") ./.)
    ];
  };

  # The daemon is the one component whose failure cannot be repaired by
  # pushing a commit, so it stays on the standard library.
  vendorHash = null;
  __darwinAllowLocalNetworking = true;

  meta = {
    description = "Switches this host to each upstream dotfiles commit that passes CI";
    mainProgram = "dotfiles-upgraded";
    platforms = lib.platforms.unix;
  };
}
