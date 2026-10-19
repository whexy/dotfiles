# Flake that re-exports a nixpkgs input with allowUnfree, for the `nixpkgs`
# registry entry. Pure flake evaluation ignores NIXPKGS_ALLOW_UNFREE and
# ~/.config/nixpkgs, so `nixpkgs#pkg` can only see unfree packages if the
# flake it resolves to sets the config itself.
{
  runCommandLocal,
  writeText,
  nixpkgs,
}:
let
  original = {
    type = "path";
    path = "${nixpkgs}";
  };

  # Locked to the store path the caller already holds, so resolving the
  # registry entry never fetches.
  lock = {
    nodes = {
      nixpkgs = {
        inherit original;
        locked = original // {
          inherit (nixpkgs) lastModified narHash rev;
        };
      };
      root.inputs.nixpkgs = "nixpkgs";
    };
    root = "root";
    version = 7;
  };

  flake = writeText "flake.nix" ''
    {
      inputs.nixpkgs.url = "path:${nixpkgs}";

      outputs =
        { nixpkgs, ... }:
        nixpkgs.outputs
        // {
          legacyPackages = builtins.mapAttrs (
            system: _:
            import nixpkgs {
              inherit system;
              config.allowUnfree = true;
              # nixpkgs' own legacyPackages carry the flake's versioned lib;
              # without it, packages embedding lib.version miss the cache.
              overlays = [ (_: _: { inherit (nixpkgs) lib; }) ];
            }
          ) nixpkgs.legacyPackages;
        };
    }
  '';
in
runCommandLocal "nixpkgs-unfree" { } ''
  mkdir $out
  cp ${flake} $out/flake.nix
  cp ${writeText "flake.lock" (builtins.toJSON lock)} $out/flake.lock
''
