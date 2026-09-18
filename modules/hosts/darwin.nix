{ flake, ... }:

{
  imports = flake.lib.importDir ./. {
    exclude = [ "nixos.nix" ];
    excludeExact = [ "darwin.nix" ];
  };
}
