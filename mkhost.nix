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
  lib = inputs.nixpkgs.lib;

  # Derive nixpkgs tags from caps and platform flags
  # Mapping: base -> unstable, dev -> llm-tools + op-wrap, wsl -> op-wsl + ssh-wsl
  nixpkgsTags = lib.flatten [
    (lib.optional (builtins.elem "base" caps) "unstable")
    (lib.optionals (builtins.elem "dev" caps) [
      "llm-tools"
      "op-wrap"
    ])
    (lib.optionals wsl [
      "op-wsl"
      "ssh-wsl"
    ])
  ];

  nixpkgsSettings = import ./overlays/nixpkgs-settings.nix {
    inherit inputs;
    tags = nixpkgsTags;
  };

  # Included config files
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
    nixpkgsSettings.nixpkgsModule

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
      home-manager.extraSpecialArgs = { inherit darwin wsl; };
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
        inherit wsl;
      };
    }

    # Hostname
    {
      networking.hostName = hostname;
    }

    (if wsl then inputs.nixos-wsl.nixosModules.wsl else { })
  ];
}
