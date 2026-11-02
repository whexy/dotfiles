# T3 Code: its server, published on the tailnet and through a public tunnel,
# the desktop app, the t3-pair helper, and the SSH device host.
#
# This file declares the options and installs the package; each part has its
# own file beside it.
args@{
  config,
  lib,
  pkgs,
  perSystem,
  ...
}:
let
  cfg = config.dotfiles.t3code;

  privacy = import ./privacy.nix { inherit lib pkgs; };

  # The daemon's cache for integrated homes, the user's own for standalone ones.
  ciCache = args.osConfig.dotfiles.nix.ciCache.enable or false || config.dotfiles.nix.ciCache.enable;
in
{
  imports = [
    ./policy.nix
    ./server.nix
    ./claude-models.nix
    ./desktop.nix
  ];

  options.dotfiles.t3code = {
    enable = lib.mkEnableOption "T3 Code, the web GUI for coding agents, and its Claude gateway models";
    package = lib.mkOption {
      type = lib.types.package;
      # The nightly server package contains only T3's server runtime.
      # Provider CLIs remain on the Home Manager profile PATH with their
      # existing wrappers.
      default = if cfg.fork.enable then perSystem.self.t3code-fork else perSystem.self.t3code-nightly;
      defaultText = lib.literalExpression "t3code-fork where fork.enable is set, else the pinned nightly package";
      description = "T3 Code package.";
    };
    finalPackage = lib.mkOption {
      type = lib.types.package;
      internal = true;
      readOnly = true;
      default = privacy.wrap cfg.package;
      description = "The package with the privacy environment bound to its programs; what the home installs and runs.";
    };
    fork.enable = lib.mkEnableOption ''
      whexy/t3code's server (t3code-fork), which applies
      programs.t3code.policy, in place of upstream's prebuilt nightly. Only an
      x86_64-linux host that substitutes from ci-cache takes it: anywhere
      else, and for a locked revision older than the cache's 48-hour expiry,
      Nix compiles it from source
    '';
    server = {
      enable = lib.mkOption {
        type = lib.types.bool;
        # Standalone homes have no osConfig to say whether this machine is
        # on the tailnet, so they enable the server themselves.
        default = args.osConfig.dotfiles.network.tailscale.enable or false;
        defaultText = lib.literalExpression "osConfig.dotfiles.network.tailscale.enable or false";
        description = ''
          Whether to run the T3 Code server. It listens on loopback only,
          for Tailscale Serve and the Cloudflare tunnel to publish.
        '';
      };
      tailnet.enable = lib.mkOption {
        type = lib.types.bool;
        default = args.osConfig.dotfiles.network.tailscale.enable or false;
        defaultText = lib.literalExpression "osConfig.dotfiles.network.tailscale.enable or false";
        description = ''
          Whether to publish the server on the tailnet through Tailscale
          Serve at `https://<MagicDNS name>:35338`.
        '';
      };
      tunnel = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = cfg.server.enable;
          defaultText = lib.literalExpression "config.dotfiles.t3code.server.enable";
          description = ''
            Whether to publish the server on the public internet through a
            Cloudflare tunnel at the host's `flake.lib.publicHost "t3"` name. The
            host creates its own tunnel and DNS record on first start with the
            shared `cloudflared-cert` secret. The server's own pairing is the
            only gate in front of it.
          '';
        };
      };
    };
    deviceHost.enable = lib.mkOption {
      type = lib.types.bool;
      # A Mac that manages Xcode has the simulators other T3 servers drive.
      default = args.osConfig.dotfiles.system.xcodes.enable or false;
      defaultText = lib.literalExpression "osConfig.dotfiles.system.xcodes.enable or false";
      description = ''
        Whether this machine serves as a T3 Code SSH device host, whose iOS
        simulators other T3 servers drive over SSH. Their probe and device
        tools run `node` from the non-interactive SSH PATH, so this puts
        Node.js on the profile.
      '';
    };
    pair.enable = lib.mkEnableOption "the t3-pair helper, which mints pairing URLs for T3 Code servers";
    desktop.enable = lib.mkEnableOption ''
      the T3 Code desktop app. Where this host runs the server, the app has
      no local environment of its own and connects to that server once
      paired with `t3-pair`
    '';
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.fork.enable -> pkgs.stdenv.hostPlatform.system == "x86_64-linux" && ciCache;
        message = "dotfiles.t3code.fork.enable requires x86_64-linux and ci-cache (dotfiles.nix.ciCache.enable), or the fork compiles from source.";
      }
    ];

    home.packages = [
      cfg.finalPackage
    ]
    ++ lib.optional cfg.pair.enable perSystem.self.t3-pair
    # pkgs.nodejs rather than a pinned major: editor.javascript installs it
    # too, and two different nodes would collide in the profile.
    ++ lib.optional cfg.deviceHost.enable pkgs.nodejs;
  };
}
