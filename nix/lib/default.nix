{ inputs, flake, ... }:
let
  inherit (inputs.nixpkgs) lib;

  overlays = {
    container-darwin = import ../overlays/container-darwin.nix;
    direnv-darwin = import ../overlays/direnv-darwin.nix;
    lkl-bigmem = import ../overlays/lkl-bigmem.nix;
    op-wsl = import ../overlays/op-wsl.nix;
    ssh-wsl = import ../overlays/ssh-wsl.nix;
    unstable = import ../overlays/unstable.nix { inherit (inputs) nixpkgs-unstable; };
    llm-tools = import ../overlays/llm-tools.nix { inherit (inputs) llm-agents; };
  };

  moduleValuesForCaps = modules: caps: builtins.map (cap: modules.${cap}) caps;

  hostOptionsModule =
    {
      caps,
      hostName,
      username,
      wsl,
    }:
    { lib, ... }:
    {
      options.dotfiles.host = {
        caps = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          description = "Capability modules enabled for this host.";
        };

        hostName = lib.mkOption {
          type = lib.types.str;
          description = "Host output and runtime hostname.";
        };

        username = lib.mkOption {
          type = lib.types.str;
          description = "Primary user for this host.";
        };

        wsl = lib.mkOption {
          type = lib.types.bool;
          description = "Whether this host runs under WSL.";
        };
      };

      config.dotfiles.host = {
        inherit
          caps
          hostName
          username
          wsl
          ;
      };
    };
in
{
  inherit overlays;

  nixosModulesForCaps = caps: moduleValuesForCaps flake.nixosModules caps;
  darwinModulesForCaps = caps: moduleValuesForCaps flake.darwinModules caps;
  homeModulesForCaps = caps: moduleValuesForCaps flake.homeModules caps;

  nixosHost =
    {
      system,
      hostName,
      username ? "whexy",
      caps,
      modules ? [ ],
      overlays ? [ ],
      wsl ? false,
    }:
    [
      inputs.disko.nixosModules.disko
      flake.nixosModules.nix-settings
      flake.nixosModules.options-monitors
      flake.nixosModules.options-keyboards
      flake.nixosModules.options-display
      flake.nixosModules.user-whexy
      (hostOptionsModule {
        inherit
          caps
          hostName
          username
          wsl
          ;
      })
      {
        nixpkgs = {
          hostPlatform = system;
          inherit overlays;
        };
        networking.hostName = hostName;

        _module.args = { inherit username wsl; };

        home-manager = {
          backupFileExtension = "backup";
          extraSpecialArgs = {
            inherit inputs flake wsl;
            darwin = false;
          };
        };
      }
    ]
    ++ moduleValuesForCaps flake.nixosModules caps
    ++ modules
    ++ lib.optionals wsl [ inputs.nixos-wsl.nixosModules.wsl ];

  darwinHost =
    {
      system,
      hostName,
      username ? "whexy",
      caps,
      modules ? [ ],
      overlays ? [ ],
      home,
    }:
    {
      class = "nix-darwin";
      value = inputs.nix-darwin.lib.darwinSystem {
        inherit system;
        modules = [
          flake.darwinModules.nix-settings
          flake.darwinModules.options-keyboards
          flake.darwinModules.options-display
          flake.darwinModules.user-whexy
          inputs.home-manager-darwin.darwinModules.home-manager
          (hostOptionsModule {
            inherit caps hostName username;
            wsl = false;
          })
          {
            nixpkgs = {
              hostPlatform = system;
              inherit overlays;
            };
            networking.hostName = hostName;

            _module.args = {
              inherit username;
              wsl = false;
            };

            home-manager = {
              useGlobalPkgs = true;
              useUserPackages = true;
              backupFileExtension = "backup";
              extraSpecialArgs = {
                inherit inputs flake;
                darwin = true;
                wsl = false;
              };
              users.${username}.imports = [ home ];
            };
          }
        ]
        ++ moduleValuesForCaps flake.darwinModules caps
        ++ modules;
        specialArgs = {
          inherit inputs flake hostName;
        };
      };
    };

  mkStandaloneHome =
    {
      system,
      modules,
      overlays ? [ ],
    }:
    let
      pkgs = import inputs.nixpkgs {
        inherit system overlays;
        config.allowUnfree = true;
      };
    in
    inputs.home-manager.lib.homeManagerConfiguration {
      inherit pkgs modules;
      extraSpecialArgs = {
        inherit inputs flake;
        darwin = false;
        wsl = false;
      };
    };
}
