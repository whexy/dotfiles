{ flake, inputs, ... }:
flake.lib.mkNixOSHostModule {
  profile = import ./profile.nix;
  inherit inputs;
}
