{
  pkgs,
  config,
  lib,
  perSystem,
  flake,
  gitConfig,
  hostName,
}:
let
  cfg = config.dotfiles.agents.t3code;
  inherit (pkgs.stdenv.hostPlatform) isDarwin;

  # The nightly server package contains only T3's server runtime. Provider
  # CLIs remain on the Home Manager profile PATH with their existing wrappers.
  t3code = if cfg.package == null then perSystem.self.t3code-nightly else cfg.package;

  # T3 treats an executable at this path as its installed preview browser; the
  # package's patched copy replaces the download that cannot run on NixOS.
  browser = t3code.browser or null;
  browserDir = ".t3/tools/chrome-headless-shell/${browser.platform}/${browser.version}";
  linkBrowser = cfg.server.enable && browser != null;

  t3 = lib.getExe' t3code "t3";

  # Tailnet clients reach the server through Tailscale Serve, which proxies to
  # this loopback port; LAN clients connect to it directly.
  port = 3773;

  lanAddress = lib.escapeShellArgs (
    [ (lib.getExe perSystem.self.lan-address) ]
    ++ lib.optionals (cfg.server.lanInterface != null) [
      "--interface"
      cfg.server.lanInterface
    ]
  );

  publish = {
    tailnet = ''
      # A new host starts this service before anyone logs in to the tailnet, and
      # t3 only warns when `tailscale serve` fails, leaving the server
      # unreachable.
      until [ "$(tailscale status --json 2>/dev/null | ${lib.getExe pkgs.jq} -r .BackendState)" = Running ]; do
        sleep 10
      done
      exec ${t3} serve \
        --host 127.0.0.1 --port ${toString port} \
        --tailscale-serve --tailscale-serve-port 35338 --no-browser
    '';

    # Binding the LAN address rather than 0.0.0.0 keeps the server off public
    # interfaces, container bridges, and VPNs. User services cannot wait for
    # the system's network, so at boot there may be no address yet.
    lan = ''
      until address=$(${lanAddress} 2>/dev/null); do
        if [ -z "''${waiting-}" ]; then
          echo "t3-serve: no private LAN IPv4 address yet, waiting" >&2
          waiting=1
        fi
        sleep 10
      done
      ${t3} serve --host "$address" --port ${toString port} --no-browser &
      server=$!
      # t3 cannot move its socket to a new address. A socket whose address
      # disappears keeps listening and works again once the address returns,
      # so only a different address restarts the server, and only when two
      # checks in a row agree: a brief flap must not end running sessions.
      moved=""
      while sleep 10 && kill -0 "$server" 2>/dev/null; do
        current=$(${lanAddress} 2>/dev/null) || current=""
        if [ -z "$current" ] || [ "$current" = "$address" ]; then
          moved=""
        elif [ "$current" = "$moved" ]; then
          echo "t3-serve: LAN address moved from $address to $current, restarting" >&2
          kill "$server"
          wait "$server"
          exit 1
        else
          moved=$current
        fi
      done
      wait "$server"
    '';
  };

  # Service managers start with a bare environment; source the same session
  # variables and profile PATH a login shell would get.
  serve = pkgs.writeShellScript "t3-serve" (
    ''
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
      # T3 sessions arrive without SSH, so no forwarded signing agent ever
      # reaches its git actions or terminal panel; commit unsigned as agents do.
      export GIT_CONFIG_GLOBAL=${gitConfig}
      cd ${lib.escapeShellArg config.home.homeDirectory}
    ''
    + publish.${cfg.server.network}
  );

  tunnel = {
    name = "t3-${hostName}";
    hostname = flake.lib.t3PublicHost hostName;
    credentials = "${config.xdg.stateHome}/t3code-tunnel/credentials.json";
  };

  tunnelConfig = (pkgs.formats.yaml { }).generate "t3code-tunnel.yml" {
    tunnel = tunnel.name;
    credentials-file = tunnel.credentials;
    ingress = [
      {
        inherit (tunnel) hostname;
        service = "http://127.0.0.1:${toString port}";
      }
      { service = "http_status:404"; }
    ];
  };

  # Every host shares one `cloudflared tunnel login` cert, so a new host
  # creates its own tunnel and DNS record here instead of being set up by hand.
  publishTunnel = pkgs.writeShellApplication {
    name = "t3code-tunnel";
    runtimeInputs = [
      pkgs.cloudflared
      pkgs.coreutils
    ];
    text = ''
      # agenix may decrypt after this starts; failing lets the service retry.
      cert="${config.age.secrets.cloudflared-cert.path}"
      if [ ! -s "$cert" ]; then
        echo "t3code-tunnel: secret is not ready: $cert" >&2
        exit 1
      fi
      export TUNNEL_ORIGIN_CERT="$cert"

      credentials=${lib.escapeShellArg tunnel.credentials}
      if [ ! -s "$credentials" ]; then
        mkdir -p ${lib.escapeShellArg (dirOf tunnel.credentials)}
        # The tunnel outlives this file, e.g. after a reinstall, and its name
        # stays taken, so recover its credentials before creating one.
        cloudflared tunnel token --cred-file "$credentials" ${tunnel.name} ||
          cloudflared tunnel create --cred-file "$credentials" ${tunnel.name}
      fi

      cloudflared tunnel route dns --overwrite-dns ${tunnel.name} ${tunnel.hostname}
      exec cloudflared tunnel --no-autoupdate --config ${tunnelConfig} run
    '';
  };

in
{
  packages = [ t3code ] ++ lib.optional cfg.pair.enable perSystem.self.t3-pair;

  homeFiles = lib.optionalAttrs linkBrowser {
    ${browserDir}.source = browser;
  };

  # A server that ran before this link existed left its own download here,
  # which Home Manager would otherwise refuse to replace.
  activation = lib.optionalAttrs linkBrowser {
    t3codeBrowser = lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
      browser="$HOME/${browserDir}"
      if [ -d "$browser" ] && [ ! -L "$browser" ]; then
        run rm -rf $VERBOSE_ARG "$browser"
      fi
    '';
  };

  systemdUserServices =
    lib.optionalAttrs (cfg.server.enable && !isDarwin) {
      t3code = {
        Unit.Description =
          {
            tailnet = "T3 Code server, published on the tailnet";
            lan = "T3 Code server, published on the LAN";
          }
          .${cfg.server.network};
        Service = {
          ExecStart = "${serve}";
          Restart = "on-failure";
          RestartSec = 10;
        };
        Install.WantedBy = [ "default.target" ];
      };
    }
    // lib.optionalAttrs (cfg.server.tunnel.enable && !isDarwin) {
      t3code-tunnel = {
        Unit = {
          Description = "Cloudflare tunnel publishing the T3 Code server at ${tunnel.hostname}";
          After = [ "agenix.service" ];
          Wants = [ "agenix.service" ];
        };
        Service = {
          ExecStart = lib.getExe publishTunnel;
          Restart = "on-failure";
          RestartSec = 10;
        };
        Install.WantedBy = [ "default.target" ];
      };
    };

  launchdAgents =
    lib.optionalAttrs (cfg.server.enable && isDarwin) {
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
    }
    // lib.optionalAttrs (cfg.server.tunnel.enable && isDarwin) {
      t3code-tunnel = {
        enable = true;
        config = {
          ProgramArguments = [ (lib.getExe publishTunnel) ];
          RunAtLoad = true;
          KeepAlive.SuccessfulExit = false;
          StandardOutPath = "${config.home.homeDirectory}/Library/Logs/t3code-tunnel.log";
          StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/t3code-tunnel.log";
        };
      };
    };
}
