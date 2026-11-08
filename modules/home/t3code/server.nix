# The T3 Code server as a user service, its Tailscale route, its public
# tunnel, and the preview browser it drives.
{
  config,
  lib,
  pkgs,
  flake,
  ...
}:
let
  cfg = config.dotfiles.t3code;

  services = import ./services.nix {
    inherit pkgs lib cfg;
    inherit (pkgs.stdenv.hostPlatform) isDarwin;
    inherit (flake.lib.t3) port tailnetPort;
    t3 = lib.getExe' cfg.finalPackage "t3";
    policy = cfg.policy.resolver;
    inherit (config.home) profileDirectory homeDirectory;
    stateHome = config.xdg.stateHome;
    inherit (config.dotfiles.agents.launcher) gitConfig;
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

    dotfiles.tunnels.services.t3code-tunnel = lib.mkIf cfg.server.tunnel.enable {
      service = "t3";
      inherit (flake.lib.t3) port;
      description = "the T3 Code server";
    };

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
