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
    tailscale-security = import ../overlays/tailscale-security.nix;
    llm-tools = import ../overlays/llm-tools.nix { inherit (inputs) llm-agents; };
  };

  moduleValuesForCaps = modules: caps: builtins.map (cap: modules.${cap}) caps;

  hostOptionsModule =
    {
      caps,
      hostName,
      username,
      wsl,
      tailscale,
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

        tailscale = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Whether this host is connected to the tailnet (Tailscale).";
        };
      };

      config.dotfiles.host = {
        inherit
          caps
          hostName
          username
          wsl
          tailscale
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
      tailscale ? true,
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
          tailscale
          ;
      })
      {
        nixpkgs = {
          hostPlatform = system;
          inherit overlays;
        };
        networking.hostName = hostName;

        _module.args = { inherit username wsl; };

        # blueprint wires home-manager for this host: it imports the HM NixOS
        # module, discovers users from hosts/<host>/users/*, injects perSystem
        # via sharedModules, and sets extraSpecialArgs { inputs, flake }.
        home-manager = {
          backupFileExtension = "backup";
          extraSpecialArgs = {
            inherit wsl;
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
      tailscale ? true,
    }:
    [
      flake.darwinModules.nix-settings
      flake.darwinModules.options-keyboards
      flake.darwinModules.options-display
      flake.darwinModules.user-whexy
      (hostOptionsModule {
        inherit
          caps
          hostName
          username
          tailscale
          ;
        wsl = false;
      })
      {
        nixpkgs = {
          hostPlatform = system;
          # blueprint injects nixpkgs.pkgs built from inputs.nixpkgs (the NixOS
          # branch) with mkDefault priority; keep darwin hosts on the
          # nixpkgs-darwin branch instead.
          pkgs = import inputs.nixpkgs-darwin {
            inherit system;
            config.allowUnfree = true;
          };
          inherit overlays;
        };
        networking.hostName = hostName;

        _module.args = {
          inherit username;
          wsl = false;
        };

        # blueprint wires home-manager for this host: it imports the HM darwin
        # module, discovers users from hosts/<host>/users/*, injects perSystem
        # via sharedModules, sets useGlobalPkgs/useUserPackages, and sets
        # extraSpecialArgs { inputs, flake }.
        home-manager = {
          backupFileExtension = "backup";
          extraSpecialArgs = {
            darwin = true;
            wsl = false;
          };
        };
      }
    ]
    ++ moduleValuesForCaps flake.darwinModules caps
    ++ modules;
}
