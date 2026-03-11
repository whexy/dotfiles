# Function to create a host
{
  inputs,
  self,
  nixConfig,
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
  # Mapping: base -> unstable, dev -> llm-tools, wsl -> op-wsl + ssh-wsl
  # virtualbox/proxmox hardware -> lkl-bigmem (for large disk image builds)
  nixpkgsTags = lib.flatten [
    (lib.optional (builtins.elem "base" caps) "unstable")
    (lib.optionals (builtins.elem "dev" caps) [
      "llm-tools"
    ])
    (lib.optionals wsl [
      "op-wsl"
      "ssh-wsl"
    ])
    (lib.optional (builtins.elem hardware [
      "virtualbox"
      "proxmox"
    ]) "lkl-bigmem")
  ];

  nixpkgsSettings = import ./overlays/nixpkgs-settings.nix {
    inherit inputs;
    tags = nixpkgsTags;
  };

  # Included config files
  hardwareConfig = ./hardware/${hardware}.nix;
  userConfig = if darwin then ./users/${username}/darwin.nix else ./users/${username}/nixos.nix;
  platformSuffix = if darwin then "darwin" else "nixos";
  systemConfigs = builtins.filter builtins.pathExists (
    map (cap: ./system/${cap}-${platformSuffix}.nix) caps
  );
  homeConfigs = builtins.filter builtins.pathExists (map (cap: ./home/${cap}.nix) caps);

  systemFunc = if darwin then inputs.nix-darwin.lib.darwinSystem else inputs.nixpkgs.lib.nixosSystem;
  hm = if darwin then inputs.home-manager-darwin.darwinModules else inputs.home-manager.nixosModules;
in
systemFunc {
  inherit system;

  modules = [
    # Custom NixOS options (hardware.monitors, etc.)
    ./options/monitors.nix

    # Global Nix Setting
    {
      nix.settings = {
        experimental-features = [
          "nix-command"
          "flakes"
        ];
        warn-dirty = false;
      }
      // nixConfig;
    }

    # Global Nixpkgs Config (overlays, ...)
    nixpkgsSettings.nixpkgsModule

    # Host Spec
    hardwareConfig
  ]
  ++ lib.optionals (!darwin) [
    inputs.disko.nixosModules.disko
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
      home-manager.extraSpecialArgs = { inherit inputs darwin wsl; };
      home-manager.users.${username} = {
        imports = homeConfigs ++ [
          inputs.agenix.homeManagerModules.default
        ];
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
