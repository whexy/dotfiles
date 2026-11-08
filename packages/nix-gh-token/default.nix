{ pkgs }:

# Materialises the GitHub CLI's token as a nix.conf fragment so `nix` can fetch
# private `github:` flakes. Writing a fragment rather than exporting NIX_CONFIG
# keeps the token out of the environment of every process `nix run` spawns.
#
# A token GitHub rejects removes the fragment instead of leaving a stale one: a
# scoped-but-invalid token makes every fetch under that scope fail with HTTP
# 401, which is strictly worse than having no token at all. Anything short of
# that verdict (offline, keyring still locked at boot, `gh` logged out) says
# nothing about the token already written, so the fragment is left as it is.
pkgs.writeShellApplication {
  name = "nix-gh-token";
  runtimeInputs = [
    pkgs.coreutils
    pkgs.gh
  ];
  text = builtins.readFile ./nix-gh-token.sh;
}
