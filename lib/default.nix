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

  # Overlays every host and standalone home applies. The Darwin workarounds
  # gate themselves on the platform, so they are inert elsewhere.
  commonOverlays = [
    overlays.unstable
    overlays.llm-tools
    overlays.container-darwin
    overlays.direnv-darwin
  ];

  # Caps are preset modules, not options. They assign feature options with
  # lib.mkDefault; hosts override individual values with plain assignments.
  capsModules = caps: map (cap: ../modules/caps/${cap}.nix) caps;
  homeCapsModules = caps: map (cap: ../modules/home/caps/${cap}.nix) caps;
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
    commonOverlays
    capsModules
    homeCapsModules
    ;

  importDir = import ./importDir.nix { inherit lib; };

  t3 = import ./t3.nix { inherit tailnetHost; };

  userService = import ./user-service.nix;

  secretEnv = import ./secret-env.nix { inherit lib; };

  agenixDecrypt = import ./agenix-decrypt.nix;

  agentPolicy = import ./agent-policy.nix;

  inherit updater;

  skillRepo = import ./skill-repo.nix { inherit inputs updater; };

  npmTarball = import ./npm-tarball.nix;

  pythonChecks = import ./python-checks;

  platformBinary = import ./platform-binary.nix;

  nixosHost =
    {
      system,
      hostName,
      username ? "whexy",
      caps,
      modules ? [ ],
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
      {
        dotfiles.host = {
          inherit
            system
            hostName
            username
            wsl
            ;
        };
        nixpkgs = {
          hostPlatform = system;
          # op-wsl swaps 1Password's CLI for the Windows one, so these apply
          # only under WSL.
          overlays =
            lib.optionals wsl [
              overlays.op-wsl
              overlays.ssh-wsl
              overlays.tailscale-wsl
            ]
            ++ commonOverlays;
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
    ++ lib.optionals wsl [
      inputs.nixos-wsl.nixosModules.wsl
      { dotfiles.platform.wsl.enable = true; }
    ]
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
    }:
    [
      # External option providers. Their behavior remains inert until a
      # dotfiles feature supplies actual configuration.
      inputs.agenix.darwinModules.default
      ../modules/hosts/darwin.nix
      {
        dotfiles.host = {
          inherit system hostName username;
        };
        nixpkgs = {
          hostPlatform = system;
          # Blueprint's injected pkgs follows the NixOS nixpkgs input; keep
          # Darwin hosts on the dedicated nixpkgs-darwin branch.
          pkgs = import inputs.nixpkgs-darwin {
            inherit system;
            config.allowUnfree = true;
          };
          overlays = commonOverlays;
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
