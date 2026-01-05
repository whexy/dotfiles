# Host configuration for mac mini
{
  self,
  nix-darwin,
  nixpkgs-unstable,
  home-manager,
  username,
  ...
}:
nix-darwin.lib.darwinSystem {
  system = "aarch64-darwin";

  modules = [
    ../../system/personal.nix
    ../../system/macos.nix
    ../../system/macos-desktop.nix

    home-manager.darwinModules.home-manager

    (
      { pkgs, ... }:
      {
        networking.hostName = "mac-mini";

        # User configuration
        users.users.${username} = {
          description = username;
          home = "/Users/${username}";
          shell = pkgs.zsh;
          openssh.authorizedKeys.keys = [
            "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMdMvHl7VPzajwBjWw+pqcLatA42yWtQKiEPj/9VqI9i"
          ];
        };

        home-manager.useGlobalPkgs = true;
        home-manager.useUserPackages = true;
        home-manager.backupFileExtension = "backup";
      }
    )

  ];

  specialArgs = {
    inherit self username;
    inputs = { inherit nixpkgs-unstable; };
  };
}
