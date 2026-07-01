{ inputs, flake, ... }:
let
  inherit (inputs.nixpkgs) lib;

  overlaysForTags =
    tags:
    let
      hasTag = tag: builtins.elem tag tags;
    in
    lib.flatten [
      (lib.optional (hasTag "container-darwin") (import ../overlays/container-darwin.nix))
      (lib.optional (hasTag "direnv-darwin") (import ../overlays/direnv-darwin.nix))
      (lib.optional (hasTag "lkl-bigmem") (import ../overlays/lkl-bigmem.nix))
      (lib.optional (hasTag "op-wsl") (import ../overlays/op-wsl.nix))
      (lib.optional (hasTag "ssh-wsl") (import ../overlays/ssh-wsl.nix))
      (lib.optional (hasTag "unstable") (
        import ../overlays/unstable.nix { inherit (inputs) nixpkgs-unstable; }
      ))
      (lib.optional (hasTag "llm-tools") (
        import ../overlays/llm-tools.nix { inherit (inputs) llm-agents; }
      ))
    ];

  tagsFor =
    {
      caps,
      darwin ? false,
      wsl ? false,
      hardware ? null,
    }:
    lib.flatten [
      (lib.optional (builtins.elem "base" caps) "unstable")
      (lib.optionals (builtins.elem "dev" caps || builtins.elem "dev-lite" caps) [ "llm-tools" ])
      (lib.optionals wsl [
        "op-wsl"
        "ssh-wsl"
      ])
      (lib.optionals darwin [
        "container-darwin"
        "direnv-darwin"
      ])
      (lib.optional (builtins.elem hardware [
        "virtualbox"
        "proxmox"
      ]) "lkl-bigmem")
    ];

  moduleValuesForCaps =
    modules: caps:
    builtins.map (cap: modules.${cap}) (builtins.filter (cap: builtins.hasAttr cap modules) caps);
in
{
  inherit overlaysForTags tagsFor;

  nixpkgsModuleFor = args: {
    nixpkgs = {
      config.allowUnfree = true;
      overlays = overlaysForTags (tagsFor args);
    };
  };

  nixosModulesForCaps = caps: moduleValuesForCaps flake.nixosModules caps;
  darwinModulesForCaps = caps: moduleValuesForCaps flake.darwinModules caps;
  homeModulesForCaps = caps: moduleValuesForCaps flake.homeModules caps;

  mkStandaloneHome =
    {
      system,
      caps,
    }:
    let
      tags = tagsFor { inherit caps; };
      pkgs = import inputs.nixpkgs {
        inherit system;
        config.allowUnfree = true;
        overlays = overlaysForTags tags;
      };
    in
    inputs.home-manager.lib.homeManagerConfiguration {
      inherit pkgs;
      extraSpecialArgs = {
        inherit inputs;
        darwin = false;
        wsl = false;
      };
      modules = moduleValuesForCaps flake.homeModules caps ++ [
        {
          home.username = builtins.getEnv "USER";
          home.homeDirectory = builtins.getEnv "HOME";
          targets.genericLinux.enable = true;
          targets.genericLinux.gpu.enable = false;
        }
      ];
    };

  mkNixOSHostModule =
    { profile, inputs }:
    let
      wsl = profile.wsl or false;
    in
    {
      imports = [
        flake.nixosModules.nix-settings
        flake.nixosModules.options-monitors
        flake.nixosModules.options-keyboards
        flake.nixosModules.options-display
        (flake.lib.nixpkgsModuleFor {
          inherit (profile) caps hardware;
          inherit wsl;
        })
        flake.nixosModules.${profile.hardware}
        inputs.disko.nixosModules.disko
      ]
      ++ flake.lib.nixosModulesForCaps profile.caps
      ++ [ flake.nixosModules.user-whexy ]
      ++ lib.optionals wsl [ inputs.nixos-wsl.nixosModules.wsl ];

      nixpkgs.hostPlatform = profile.system;
      networking.hostName = profile.hostname;

      _module.args = {
        inherit (profile) username;
        inherit wsl;
      };

      home-manager = {
        backupFileExtension = "backup";
        extraSpecialArgs = {
          inherit inputs wsl;
          darwin = false;
        };
      };
    };

  mkDarwinHost =
    { profile, userHome }:
    {
      class = "nix-darwin";
      value = inputs.nix-darwin.lib.darwinSystem {
        inherit (profile) system;
        modules = [
          flake.darwinModules.nix-settings
          flake.darwinModules.options-keyboards
          flake.darwinModules.options-display
          (flake.lib.nixpkgsModuleFor {
            inherit (profile) caps hardware;
            darwin = true;
          })
          flake.darwinModules.${profile.hardware}
        ]
        ++ flake.lib.darwinModulesForCaps profile.caps
        ++ [
          flake.darwinModules.user-whexy
          inputs.home-manager-darwin.darwinModules.home-manager
          {
            nixpkgs.hostPlatform = profile.system;
            networking.hostName = profile.hostname;

            _module.args = {
              inherit (profile) username;
              wsl = false;
            };

            home-manager = {
              useGlobalPkgs = true;
              useUserPackages = true;
              backupFileExtension = "backup";
              extraSpecialArgs = {
                inherit inputs;
                darwin = true;
                wsl = false;
              };
              users.${profile.username}.imports = [ userHome ];
            };
          }
        ];
        specialArgs = {
          inherit inputs;
          hostName = profile.hostname;
        };
      };
    };
}
