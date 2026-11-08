# Publishes loopback HTTP services on the public internet, each through a
# Cloudflare tunnel of its own, run as a user service.
#
# Every host shares one `cloudflared tunnel login` cert, so a new host creates
# its own tunnel and DNS record here instead of being set up by hand.
args@{
  config,
  lib,
  pkgs,
  flake,
  ...
}:
let
  cfg = config.dotfiles.tunnels;

  # A tunnel's state lives under its service's name, so renaming a service
  # makes it recover its tunnel's credentials again.
  credentials = name: "${config.xdg.stateHome}/${name}/credentials.json";

  publish =
    name: service:
    let
      tunnelConfig = (pkgs.formats.yaml { }).generate "${name}.yml" {
        inherit (service) tunnel;
        credentials-file = credentials name;
        ingress = [
          (
            {
              inherit (service) hostname;
              service = "http://127.0.0.1:${toString service.port}";
            }
            // lib.optionalAttrs (service.path != null) { inherit (service) path; }
          )
          { service = "http_status:404"; }
        ];
      };
    in
    pkgs.writeShellApplication {
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

        credentials=${lib.escapeShellArg (credentials name)}
        if [ ! -s "$credentials" ]; then
          mkdir -p ${lib.escapeShellArg (dirOf (credentials name))}
          # The tunnel outlives this file, e.g. after a reinstall, and its name
          # stays taken, so recover its credentials before creating one.
          cloudflared tunnel token --cred-file "$credentials" ${service.tunnel} ||
            cloudflared tunnel create --cred-file "$credentials" ${service.tunnel}
        fi

        cloudflared tunnel route dns --overwrite-dns ${service.tunnel} ${service.hostname}
        exec cloudflared tunnel --no-autoupdate --config ${tunnelConfig} run
      '';
    };

  userService = flake.lib.userService {
    inherit lib;
    inherit (pkgs.stdenv.hostPlatform) isDarwin;
    inherit (config.home) homeDirectory;
  };
in
{
  options.dotfiles.tunnels.hostName = lib.mkOption {
    type = lib.types.nullOr lib.types.str;
    default = args.osConfig.dotfiles.host.hostName or null;
    defaultText = lib.literalExpression "osConfig.dotfiles.host.hostName or null";
    description = ''
      Dotfiles host name each tunnel and its public name derive from.
      Standalone homes have no osConfig to supply it.
    '';
  };

  options.dotfiles.tunnels.services = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule (
        { config, ... }:
        {
          options = {
            service = lib.mkOption {
              type = lib.types.str;
              example = "t3";
              description = ''
                Short name of the published service. The public name is
                `flake.lib.publicHost` of it, and the tunnel is named
                `<service>-<hostName>`, unique across every host.
              '';
            };
            port = lib.mkOption {
              type = lib.types.port;
              description = "Loopback port of the published service.";
            };
            path = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "cloudflared path regex; requests for any other path get a 404 at the edge.";
            };
            description = lib.mkOption {
              type = lib.types.str;
              description = "What the tunnel publishes, completing \"Cloudflare tunnel publishing …\".";
            };
            tunnel = lib.mkOption {
              type = lib.types.str;
              readOnly = true;
              default = "${config.service}-${cfg.hostName}";
              description = "Cloudflare tunnel name.";
            };
            hostname = lib.mkOption {
              type = lib.types.str;
              readOnly = true;
              default = flake.lib.publicHost config.service cfg.hostName;
              description = "Public hostname.";
            };
          };
        }
      )
    );
    default = { };
    description = "Tunnels by the name of the user service that runs each.";
  };

  config = lib.mkIf (cfg.services != { }) (
    {
      # `cloudflared tunnel login` cert for the tunnels' zone: it creates
      # tunnels and edits any DNS record in that zone.
      age.secrets.cloudflared-cert.file = ../../../secrets/cloudflared-cert.age;

      assertions = [
        {
          assertion = cfg.hostName != null;
          message = "dotfiles.tunnels.services requires dotfiles.tunnels.hostName, which standalone homes set themselves.";
        }
      ];
    }
    // userService.units (
      lib.mapAttrs (name: service: {
        description = "Cloudflare tunnel publishing ${service.description} at ${service.hostname}";
        argv = [ (lib.getExe (publish name service)) ];
        wants = [ "agenix.service" ];
      }) cfg.services
    )
  );
}
