# `agenix-decrypt [age flags] <file.age>`: age --decrypt with whichever of
# the home's agenix identities this user can read. For activation steps that
# need a secret before agenix's own service has decrypted it.
{
  pkgs,
  # The home's config.age.identityPaths and config.age.package.
  identityPaths,
  package,
}:
pkgs.writeShellApplication {
  name = "agenix-decrypt";
  text = ''
    candidates=(${pkgs.lib.escapeShellArgs identityPaths})
    identities=()
    for identity in "''${candidates[@]}"; do
      [ -r "$identity" ] && identities+=(-i "$identity")
    done
    if [ ''${#identities[@]} -eq 0 ]; then
      echo "agenix-decrypt: no readable identity among: "${pkgs.lib.escapeShellArg (toString identityPaths)} >&2
      exit 1
    fi
    exec ${pkgs.lib.getExe package} --decrypt "''${identities[@]}" "$@"
  '';
}
