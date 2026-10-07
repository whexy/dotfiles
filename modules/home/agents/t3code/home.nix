{
  pkgs,
  config,
  lib,
  perSystem,
}:
let
  cfg = config.dotfiles.agents.t3code;
  inherit (pkgs.stdenv.hostPlatform) isDarwin;

  # The nightly server package contains only T3's server runtime. Provider
  # CLIs remain on the Home Manager profile PATH with their existing wrappers.
  t3code = if cfg.server.package == null then perSystem.self.t3code-nightly else cfg.server.package;

  # Every client reaches the server through Tailscale Serve, which proxies to
  # this loopback port.
  port = 3773;

  # Service managers start with a bare environment; source the same session
  # variables and profile PATH a login shell would get.
  serve = pkgs.writeShellScript "t3-serve" ''
    export PATH=${
      lib.concatStringsSep ":" [
        "${config.home.profileDirectory}/bin"
        "/run/wrappers/bin"
        "/run/current-system/sw/bin"
        "/nix/var/nix/profiles/default/bin"
        "/usr/bin"
        "/bin"
        "/usr/sbin"
        "/sbin"
      ]
    }
    . ${config.home.profileDirectory}/etc/profile.d/hm-session-vars.sh
    cd ${lib.escapeShellArg config.home.homeDirectory}
    # A new host starts this service before anyone logs in to the tailnet, and
    # t3 only warns when `tailscale serve` fails, leaving the server
    # unreachable.
    until [ "$(tailscale status --json 2>/dev/null | ${lib.getExe pkgs.jq} -r .BackendState)" = Running ]; do
      sleep 10
    done
    exec ${lib.getExe' t3code "t3"} serve \
      --host 127.0.0.1 --port ${toString port} \
      --tailscale-serve --tailscale-serve-port 35338 --no-browser
  '';

in
{
  packages =
    lib.optional cfg.server.enable t3code ++ lib.optional cfg.pair.enable perSystem.self.t3-pair;

  systemdUserServices = lib.optionalAttrs (cfg.server.enable && !isDarwin) {
    t3code = {
      Unit.Description = "T3 Code server, published on the tailnet";
      Service = {
        ExecStart = "${serve}";
        Restart = "on-failure";
        RestartSec = 10;
      };
      Install.WantedBy = [ "default.target" ];
    };
  };

  launchdAgents = lib.optionalAttrs (cfg.server.enable && isDarwin) {
    t3code = {
      enable = true;
      config = {
        ProgramArguments = [ "${serve}" ];
        RunAtLoad = true;
        KeepAlive.SuccessfulExit = false;
        StandardOutPath = "${config.home.homeDirectory}/Library/Logs/t3code.log";
        StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/t3code.log";
      };
    };
  };
}
