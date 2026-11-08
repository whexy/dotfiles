# The prebuilt archive a package fetches for one system, from the pins the
# `platform-binaries`, `manifest-checksums` and npm `prebuilds` updaters
# write: `sources` holds `version` and a hash per Nix system. `urlTemplate`
# and `platforms` (Nix system to the upstream's platform name) are the same
# values the package hands its updater, which fills {version} and {platform}
# the same way.
{
  pkgs,
  sources,
  urlTemplate,
  platforms,
  system ? pkgs.stdenv.hostPlatform.system,
}:
let
  inherit (pkgs) lib;
  platform = platforms.${system} or (throw "no prebuilt ${urlTemplate} for ${system}");
in
{
  inherit platform;
  src = pkgs.fetchurl {
    url = builtins.replaceStrings [ "{version}" "{platform}" ] [ sources.version platform ] urlTemplate;
    hash = sources.hashes.${system};
  };
  # The systems the pins cover.
  metaPlatforms = lib.attrNames sources.hashes;
}
