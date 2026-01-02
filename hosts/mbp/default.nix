# Host configuration for mbp (laptop)
{
  self,
  nix-darwin,
  nixpkgs-unstable,
  home-manager,
  ...
}:
nix-darwin.lib.darwinSystem {
  system = "aarch64-darwin";

  modules = [
    ../../modules/personal.nix
    ../../modules/macos.nix

    home-manager.darwinModules.home-manager

    ../../modules/user.nix

    {
      networking.hostName = "mbp";
      home-manager.useGlobalPkgs = true;
      home-manager.useUserPackages = true;
      home-manager.backupFileExtension = "backup";
    }

  ];

  specialArgs = {
    inherit self;
    inputs = { inherit nixpkgs-unstable; };
  };
}
