# Host configuration for pc (x86_64-linux)
{
  self,
  nixpkgs,
  nixpkgs-unstable,
  home-manager,
  ...
}:
nixpkgs.lib.nixosSystem {
  system = "x86_64-linux";

  modules = [
    ./hardware-configuration.nix

    ../../modules/personal.nix

    home-manager.nixosModules.home-manager

    {
      networking.hostName = "pc";

      system.stateVersion = "25.11";
      system.configurationRevision = self.rev or self.dirtyRev or null;

      time.timeZone = "UTC";
      networking.networkmanager.enable = true;

      users.users.whexy = {
        isNormalUser = true;
        description = "whexy";
        extraGroups = [
          "wheel"
          "networkmanager"
          "docker"
        ];
      };

      services.openssh.enable = true;
      virtualisation.docker.enable = true;

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
