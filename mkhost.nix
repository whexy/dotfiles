# Function to create a host
{
  inputs,
  self,
}:
{
  system,
  hardware,
  hostname,
  username,
  caps,
  darwin ? false,
  wsl ? false,
}:

let
  # Included config files
  nixpkgsConfig = ./overlays/nixpkgs-settings.nix;
  hardwareConfig = ./hardware/${hardware}.nix;
  userConfig = if darwin then ./users/${username}/darwin.nix else ./users/${username}/nixos.nix;
  platformSuffix = if darwin then "darwin" else "nixos";
  systemConfigs = map (cap: ./system/${cap}-${platformSuffix}.nix) caps;
  homeConfigs = map (cap: ./home/${cap}.nix) caps;

  systemFunc = if darwin then inputs.nix-darwin.lib.darwinSystem else inputs.nixpkgs.lib.nixosSystem;
  hm = if darwin then inputs.home-manager-darwin.darwinModules else inputs.home-manager.nixosModules;
in
systemFunc {
  inherit system;

  modules = [
    # Global Nix Setting
    {
      nix.settings = {
        experimental-features = [
          "nix-command"
          "flakes"
        ];
        warn-dirty = false;
      };
    }

    # Global Nixpkgs Config (overlays, ...)
    nixpkgsConfig

    # Host Spec
    hardwareConfig
  ]
  ++ systemConfigs
  ++ [

    # Create User
    userConfig

    # Home Manager
    hm.home-manager
    {
      home-manager.useGlobalPkgs = true;
      home-manager.useUserPackages = true;
      home-manager.backupFileExtension = "backup";
      home-manager.extraSpecialArgs = { inherit darwin; };
      home-manager.users.${username} = {
        imports = homeConfigs;
      };
    }

    {
      _module.args = {
        inherit inputs self;
        inherit system hostname;
        inherit username;
        inherit darwin;
      };
    }

    # Hostname
    {
      networking.hostName = hostname;
    }

    (if wsl then inputs.nixos-wsl.nixosModules.wsl else { })
  ];
}
