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
  inherit (inputs.nixpkgs) lib;

  # Derive nixpkgs tags from caps and platform flags
  # Mapping: base -> unstable, dev -> llm-tools, wsl -> op-wsl + ssh-wsl
  # virtualbox/proxmox hardware -> lkl-bigmem (for large disk image builds)
  nixpkgsTags = lib.flatten [
    (lib.optional (builtins.elem "base" caps) "unstable")
    (lib.optionals (builtins.elem "dev" caps || builtins.elem "dev-lite" caps) [
      "llm-tools"
    ])
    (lib.optionals wsl [
      "op-wsl"
      "ssh-wsl"
    ])
    (lib.optional darwin "container-darwin") # workaround: NixOS/nixpkgs#445648
    (lib.optional darwin "direnv-darwin") # workaround: NixOS/nixpkgs#507531
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
    ./options/keyboards.nix
    ./options/display.nix

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
      home-manager = {
        useGlobalPkgs = true;
        useUserPackages = true;
        backupFileExtension = "backup";
        extraSpecialArgs = { inherit inputs darwin wsl; };
        users.${username} = {
          imports =
            homeConfigs
            ++ [
              inputs.agenix.homeManagerModules.default
              inputs.nix-index-database.homeModules.default

              # Cross-platform replacement for upstream HM programs.rclone
              # (adds launchd support for Darwin). Loaded for all hosts so the
              # `programs.rclone` option set is consistent everywhere.
              ./home/modules/programs/rclone.nix
            ]
            ++ lib.optionals (builtins.elem "gui" caps) [
              # Renpho health: CLI + systemd timer (Linux) + waybar pill.
              # Modules are no-ops on Darwin so they can be imported on every
              # gui-cap host without further gating.
              inputs.renpho-health.homeModules.default
              inputs.renpho-health.homeModules.waybar
            ];
        };
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
