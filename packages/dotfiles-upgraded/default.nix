{ pkgs }:
pkgs.buildGoModule {
  pname = "dotfiles-upgraded";
  version = "0.1.0";
  src = ./.;

  # The daemon is the one component whose failure cannot be repaired by
  # pushing a commit, so it stays on the standard library.
  vendorHash = null;

  doCheck = true;

  meta = {
    description = "Polls the upstream dotfiles repo and switches this host once CI passes";
    mainProgram = "dotfiles-upgraded";
    platforms = pkgs.lib.platforms.unix;
  };
}
