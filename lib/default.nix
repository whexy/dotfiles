{ inputs, ... }:
let
  inherit (inputs.nixpkgs) lib;

  updater = import ./updater.nix { inherit lib; };

  # The auto-upgrade daemon's fleet-wide constants: upstreamRef,
  # upgradeFailureWebhook, rollout (CI reads it with `nix eval`), and
  # upgraderReload.
  upgrade = import ../packages/dotfiles-upgraded/fleet.nix { inherit lib tailnetHost; };

  # Public name of a service a host publishes through its own Cloudflare
  # tunnel; the tunnel services and t3-pair all derive names from here.
  # Keep it one label below the zone: Cloudflare's free certificate covers
  # only `*.<zone>`.
  publicHost = service: host: "${host}-${service}.clusters.work";

  # MagicDNS name of a tailnet node or ingress.
  tailnetHost = name: "${name}.at-basking.ts.net";

  overlays = {
    container-darwin = import ../overlays/container-darwin.nix;
    direnv-darwin = import ../overlays/direnv-darwin.nix;
    docker-runc-lxc = import ../overlays/docker-runc-lxc.nix;
    lkl-bigmem = import ../overlays/lkl-bigmem.nix;
    op-wsl = import ../overlays/op-wsl.nix;
    ssh-wsl = import ../overlays/ssh-wsl.nix;
    tailscale-wsl = import ../overlays/tailscale-wsl.nix;
    unstable = import ../overlays/unstable.nix { inherit (inputs) nixpkgs-unstable; };
    llm-tools = import ../overlays/llm-tools.nix { inherit (inputs) llm-agents; };
  };

  # Caps are preset modules, not options. They assign feature options with
  # lib.mkDefault; hosts override individual values with plain assignments.
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
  inherit (upgrade)
    upstreamRef
    upgradeFailureWebhook
    rollout
    upgraderReload
    ;

  inherit
    publicHost
    tailnetHost
    overlays
    capsModules
    homeCapsModules
    ;

  importDir = import ./importDir.nix { inherit lib; };

  inherit updater;

  skillRepo = import ./skill-repo.nix { inherit inputs updater; };

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
