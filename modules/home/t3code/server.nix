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
  inherit (config.dotfiles.tunnels) hostName;

  services = import ./services.nix {
    inherit pkgs lib cfg;
    t3 = lib.getExe' cfg.finalPackage "t3";
    inherit (cfg) policy;
    inherit (config.home) profileDirectory homeDirectory;
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
    assertions = [
      {
        assertion = cfg.server.tunnel.enable -> hostName != null;
        message = "dotfiles.t3code.server.tunnel.enable requires the server and dotfiles.tunnels.hostName.";
      }
    ];

    systemd.user.services = services.systemdUserServices;
    launchd.agents = services.launchdAgents;

    dotfiles.tunnels.services.t3code-tunnel = lib.mkIf cfg.server.tunnel.enable (
      let
        hostname = flake.lib.publicHost "t3" hostName;
      in
      {
        tunnel = "t3-${hostName}";
        inherit hostname;
        inherit (services) port;
        description = "Cloudflare tunnel publishing the T3 Code server at ${hostname}";
      }
    );

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
