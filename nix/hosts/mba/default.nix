{ flake, ... }:
flake.lib.mkDarwinHost {
  profile = import ./profile.nix;
  userHome = ./users/whexy/home-configuration.nix;
}
