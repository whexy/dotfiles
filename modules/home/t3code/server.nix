# The T3 Code server as a user service, its tailnet route, its public
# tunnel, the preview browser it drives, and the Rex server it opens
# sessions on.
args@{
  config,
  lib,
  pkgs,
  flake,
  ...
}:
let
  cfg = config.dotfiles.t3code;
  relayUrl = "https://${flake.lib.tailnetHost config.dotfiles.tailnetRelay.hostName}:${toString flake.lib.t3.tailnetPort}";

  services = import ./services.nix {
    inherit pkgs lib cfg;
    inherit (pkgs.stdenv.hostPlatform) isDarwin;
    inherit (flake.lib.t3) port tailnetPort;
    t3 = lib.getExe' cfg.finalPackage "t3";
    policy = cfg.policy.resolver;
    tailnetUrl = if cfg.server.relay.enable then relayUrl else null;
    publicUrl =
      if cfg.server.tunnel.enable then
        "https://${config.dotfiles.tunnels.services.t3code-tunnel.hostname}"
      else
        null;
    inherit (config.home) profileDirectory homeDirectory;
    stateHome = config.xdg.stateHome;
    inherit (config.dotfiles.agents.launcher) gitConfig;
    pushTokenPath = if cfg.server.push.enable then config.age.secrets.t3-push-host-token.path else null;
  };

  # T3 treats an executable at this path as its installed preview browser; the
  # package's patched copy replaces the download that cannot run on NixOS.
  browser = cfg.package.browser or null;
  browserDir = ".t3/tools/chrome-headless-shell/${browser.platform}/${browser.version}";
  linkBrowser = browser != null;
in
{
  config = lib.mkIf (cfg.enable && cfg.server.enable) {
    inherit (services) systemd launchd;
    age.secrets.t3-push-host-token = lib.mkIf cfg.server.push.enable {
      file = ../../../secrets/t3-push-host-token.age;
    };
    dotfiles = {
      linger.enable = lib.mkDefault true;

      # "Open in Rex" runs `rex` on this host to create the session, which a
      # Mac's Rex app then opens from its host list.
      terminal.rex.server.enable = lib.mkDefault (
        pkgs.stdenv.hostPlatform.isLinux && !(args.osConfig.services.rex.loginServer.enable or false)
      );

      tailnetRelay.serves.t3code = lib.mkIf cfg.server.relay.enable {
        port = flake.lib.t3.tailnetPort;
        target = "127.0.0.1:${toString flake.lib.t3.port}";
        tls = true;
      };

      tunnels.services.t3code-tunnel = lib.mkIf cfg.server.tunnel.enable {
        service = "t3";
        inherit (flake.lib.t3) port;
        description = "the T3 Code server";
      };
    };
    assertions = [
      {
        assertion = cfg.server.relay.enable -> config.dotfiles.tailnetRelay.enable;
        message = "dotfiles.t3code.server.relay publishes the server through dotfiles.tailnetRelay, which is off.";
      }
      {
        assertion = config.dotfiles.terminal.rex.local;
        message = "dotfiles.t3code.server opens Rex sessions on this host, so it needs a Rex server here: the Rex app (dotfiles.terminal.rex.enable) on macOS, or Rex's login server or dotfiles.terminal.rex.server on Linux.";
      }
    ];

    home = lib.mkIf linkBrowser {
      file.${browserDir}.source = browser;

      # A server that ran before this link existed left its own download here,
      # which Home Manager would otherwise refuse to replace.
      activation.t3codeBrowser = lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
        browser="$HOME/${browserDir}"
        if [ -d "$browser" ] && [ ! -L "$browser" ]; then
          run rm -rf $VERBOSE_ARG "$browser"
        fi
      '';
    };
  };
}
