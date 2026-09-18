{ flake, ... }:

{
  imports = flake.lib.importDir ./. {
    exclude = [ "darwin.nix" ];
    excludeExact = [ "nixos.nix" ];
  };
}
