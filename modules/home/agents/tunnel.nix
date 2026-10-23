# Publishes a loopback HTTP service on the public internet through a
# Cloudflare tunnel of its own, run as a user service named `name`.
#
# Every host shares one `cloudflared tunnel login` cert, so a new host creates
# its own tunnel and DNS record here instead of being set up by hand.
{
  pkgs,
  config,
  lib,
}:
{
  name,
  # Cloudflare tunnel name, unique across every host and service.
  tunnel,
  hostname,
  port,
  # cloudflared path regex; requests for any other path get a 404 at the edge.
  path ? null,
  description,
}:
let
  inherit (pkgs.stdenv.hostPlatform) isDarwin;

  credentials = "${config.xdg.stateHome}/${name}/credentials.json";

  tunnelConfig = (pkgs.formats.yaml { }).generate "${name}.yml" {
    inherit tunnel;
    credentials-file = credentials;
    ingress = [
      (
        {
          inherit hostname;
          service = "http://127.0.0.1:${toString port}";
        }
        // lib.optionalAttrs (path != null) { inherit path; }
      )
      { service = "http_status:404"; }
    ];
  };

  publish = pkgs.writeShellApplication {
    inherit name;
    runtimeInputs = [
      pkgs.cloudflared
      pkgs.coreutils
    ];
    text = ''
      # agenix may decrypt after this starts; failing lets the service retry.
      cert="${config.age.secrets.cloudflared-cert.path}"
      if [ ! -s "$cert" ]; then
        echo "${name}: secret is not ready: $cert" >&2
        exit 1
      fi
      export TUNNEL_ORIGIN_CERT="$cert"

      credentials=${lib.escapeShellArg credentials}
      if [ ! -s "$credentials" ]; then
        mkdir -p ${lib.escapeShellArg (dirOf credentials)}
        # The tunnel outlives this file, e.g. after a reinstall, and its name
        # stays taken, so recover its credentials before creating one.
        cloudflared tunnel token --cred-file "$credentials" ${tunnel} ||
          cloudflared tunnel create --cred-file "$credentials" ${tunnel}
      fi

      cloudflared tunnel route dns --overwrite-dns ${tunnel} ${hostname}
      exec cloudflared tunnel --no-autoupdate --config ${tunnelConfig} run
    '';
  };

  log = "${config.home.homeDirectory}/Library/Logs/${name}.log";
in
{
  systemdUserServices = lib.optionalAttrs (!isDarwin) {
    ${name} = {
      Unit = {
        Description = description;
        After = [ "agenix.service" ];
        Wants = [ "agenix.service" ];
      };
      Service = {
        ExecStart = lib.getExe publish;
        Restart = "on-failure";
        RestartSec = 10;
      };
      Install.WantedBy = [ "default.target" ];
    };
  };

  launchdAgents = lib.optionalAttrs isDarwin {
    ${name} = {
      enable = true;
      config = {
        ProgramArguments = [ (lib.getExe publish) ];
        RunAtLoad = true;
        KeepAlive.SuccessfulExit = false;
        StandardOutPath = log;
        StandardErrorPath = log;
      };
    };
  };
}
