{ inputs, ... }:
let
  inherit (inputs.nixpkgs) lib;

  overlays = {
    container-darwin = import ../overlays/container-darwin.nix;
    direnv-darwin = import ../overlays/direnv-darwin.nix;
    docker-runc-lxc = import ../overlays/docker-runc-lxc.nix;
    lkl-bigmem = import ../overlays/lkl-bigmem.nix;
    op-wsl = import ../overlays/op-wsl.nix;
    ssh-wsl = import ../overlays/ssh-wsl.nix;
    unstable = import ../overlays/unstable.nix { inherit (inputs) nixpkgs-unstable; };
    tailscale-security = import ../overlays/tailscale-security.nix;
    llm-tools = import ../overlays/llm-tools.nix { inherit (inputs) llm-agents; };
  };

  # Caps are preset modules, not options. They assign feature options at
  # normal priority; hosts override individual values with lib.mkForce.
  capsModules = caps: map (cap: ../modules/caps/${cap}.nix) caps;
  homeCapsModules = caps: map (cap: ../modules/home/caps/${cap}.nix) caps;

  hostOptionsModule =
    {
      system,
      hostName,
      username,
      wsl,
    }:
    { lib, ... }:
    {
      options.dotfiles.host = {
        hostName = lib.mkOption {
          type = lib.types.str;
          description = "Host output and runtime hostname.";
        };
        system = lib.mkOption {
          type = lib.types.str;
          description = "Host platform, e.g. x86_64-linux.";
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
          system
          hostName
          username
          wsl
          ;
      };
    };
in
{
  inherit
    overlays
    capsModules
    homeCapsModules
    ;

  importDir = import ./importDir.nix { inherit lib; };

  nixosHost =
    {
      system,
      hostName,
      username ? "whexy",
      caps,
      modules ? [ ],
      overlays ? [ ],
      wsl ? false,
      incusContainer ? false,
    }:
    [
      # External option providers. Their behavior remains inert until a
      # dotfiles feature supplies actual configuration.
      inputs.disko.nixosModules.disko
      inputs.agenix.nixosModules.default
      ({ modulesPath, ... }: {
        imports = [ (modulesPath + "/image/images.nix") ];
      })
      ../modules/hosts/nixos.nix
      (hostOptionsModule {
        inherit
          system
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

        # Blueprint discovers integrated users and wires Home Manager. Caps
        # are passed as preset names, not mirrored into config options.
        home-manager = {
          backupFileExtension = "backup";
          extraSpecialArgs.dotfilesCaps = caps;
        };
      }
    ]
    ++ capsModules caps
    ++ modules
    ++ lib.optionals wsl [ inputs.nixos-wsl.nixosModules.wsl ]
    # The LXC profile sets boot.isContainer unconditionally, so it cannot be
    # option-gated inside the incusContainer platform module.
    ++ lib.optionals incusContainer [
      ({ modulesPath, ... }: { imports = [ (modulesPath + "/virtualisation/lxc-container.nix") ]; })
      { dotfiles.platform.incusContainer.enable = true; }
    ];

  darwinHost =
    {
      system,
      hostName,
      username ? "whexy",
      caps,
      modules ? [ ],
      overlays ? [ ],
    }:
    [
      # External option providers. Their behavior remains inert until a
      # dotfiles feature supplies actual configuration.
      inputs.agenix.darwinModules.default
      ../modules/hosts/darwin.nix
      (hostOptionsModule {
        inherit
          system
          hostName
          username
          ;
        wsl = false;
      })
      {
        nixpkgs = {
          hostPlatform = system;
          # Blueprint's injected pkgs follows the NixOS nixpkgs input; keep
          # Darwin hosts on the dedicated nixpkgs-darwin branch.
          pkgs = import inputs.nixpkgs-darwin {
            inherit system;
            config.allowUnfree = true;
          };
          inherit overlays;
        };
        networking.hostName = hostName;

        home-manager = {
          backupFileExtension = "backup";
          extraSpecialArgs.dotfilesCaps = caps;
        };
      }
    ]
    ++ capsModules caps
    ++ modules;
}
