# Workaround: NixOS/nixpkgs#507531
# direnv test-fish gets Killed: 9 on darwin after libarchive 3.8.6 update.
# Remove this overlay once the upstream issue is resolved.
# https://github.com/NixOS/nixpkgs/issues/507531
final: prev:
prev.lib.optionalAttrs prev.stdenv.hostPlatform.isDarwin {
  direnv = prev.direnv.overrideAttrs (_: {
    doCheck = false;
  });
}
