# Host configuration for remote dev manchines (x86_64-linux)
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
    ../../system/dev.nix

    home-manager.nixosModules.home-manager

    {
      networking.hostName = "dev";

      system.stateVersion = "25.11";
      system.configurationRevision = self.rev or self.dirtyRev or null;

      # Bootloader - systemd-boot for UEFI
      boot.loader.systemd-boot.enable = true;
      boot.loader.efi.canTouchEfiVariables = true;

      time.timeZone = "America/Chicago";
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
      services.tailscale.enable = true;
      services.qemuGuest.enable = true;
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
