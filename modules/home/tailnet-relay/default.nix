# A userspace tailnet node for hosts that run no Tailscale daemon, such as
# shared servers: it relays loopback connections to tailnet services, and
# only from processes of this home's user (packages/tailnet-relay).
#
# The node joins as `tags` with an OAuth client secret, so the tailnet
# policy decides what it reaches; it serves nothing on the tailnet.
{
  config,
  lib,
  pkgs,
  perSystem,
  ...
}:
let
  cfg = config.dotfiles.tailnetRelay;

  socketUnit = name: "tailnet-relay-${name}";
  sockets = map (name: "${socketUnit name}.socket") (lib.attrNames cfg.forwards);

  relayConfig = pkgs.writeText "tailnet-relay.json" (
    builtins.toJSON {
      hostname = cfg.hostName;
      stateDir = "${config.xdg.stateHome}/tailnet-relay";
      clientSecretFile = config.age.secrets.tailnet-relay-oauth.path;
      inherit (cfg) tags;
      forwards = lib.mapAttrsToList (name: forward: {
        inherit name;
        listen = forward.address;
        inherit (forward) upstream;
      }) cfg.forwards;
    }
  );
in
{
  options.dotfiles.tailnetRelay = {
    enable = lib.mkEnableOption "the userspace tailnet relay";

    hostName = lib.mkOption {
      type = lib.types.str;
      example = "venus-relay";
      description = "Name of the relay's node on the tailnet.";
    };

    tags = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "tag:tailnet-relay" ];
      description = ''
        Tags the node joins with. The OAuth client must be allowed to
        create keys for them.
      '';
    };

    forwards = lib.mkOption {
      default = { };
      description = ''
        Tailnet HTTPS origins relayed from loopback ports, as plain HTTP. A
        feature adds its own while `enable` is set, and runs `checker` before
        each client connects.
      '';
      type = lib.types.attrsOf (
        lib.types.submodule (
          { config, ... }:
          {
            options = {
              port = lib.mkOption {
                type = lib.types.port;
                description = "Loopback port the forward listens on.";
              };
              upstream = lib.mkOption {
                type = lib.types.str;
                example = "https://cpa.at-basking.ts.net";
                description = "Tailnet origin requests are relayed to.";
              };
              address = lib.mkOption {
                type = lib.types.str;
                readOnly = true;
                # A literal address: `localhost` may resolve to ::1, which the
                # relay does not hold.
                default = "127.0.0.1:${toString config.port}";
                description = "Address clients connect to.";
              };
              url = lib.mkOption {
                type = lib.types.str;
                readOnly = true;
                default = "http://${config.address}";
                description = "Origin clients send requests to.";
              };
            };
          }
        )
      );
    };

    checker = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = lib.getExe' perSystem.self.tailnet-relay "tailnet-relay-check";
      defaultText = lib.literalMD "`tailnet-relay-check` of `packages/tailnet-relay`";
      description = ''
        Command that exits non-zero unless this user holds every forward
        address it is given. Any port is free for another user to take while
        the relay does not hold it, so every client runs this before it sends
        anything to a forward.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = pkgs.stdenv.hostPlatform.isLinux;
        message = "dotfiles.tailnetRelay needs Linux, whose sock_diag names each client's user.";
      }
      {
        assertion = cfg.forwards != { };
        message = "dotfiles.tailnetRelay is enabled with no forwards.";
      }
      {
        assertion = lib.allUnique (lib.mapAttrsToList (_: forward: forward.port) cfg.forwards);
        message = "dotfiles.tailnetRelay.forwards share a port.";
      }
    ];

    age.secrets.tailnet-relay-oauth.file = ../../../secrets/tailnet-relay-oauth.age;

    # systemd holds each port, so it stays this user's while the relay
    # restarts; a port another user took first fails its socket unit.
    systemd.user.sockets = lib.mapAttrs' (
      name: forward:
      lib.nameValuePair (socketUnit name) {
        Unit.Description = "Tailnet relay to ${forward.upstream}";
        Socket = {
          ListenStream = forward.address;
          FileDescriptorName = name;
          Service = "tailnet-relay.service";
        };
        Install.WantedBy = [ "sockets.target" ];
      }
    ) cfg.forwards;

    systemd.user.services.tailnet-relay = {
      Unit = {
        Description = "Userspace tailnet relay";
        Requires = sockets;
        After = [ "agenix.service" ] ++ sockets;
        Wants = [ "agenix.service" ];
      };
      Service = {
        ExecStart = "${lib.getExe perSystem.self.tailnet-relay} -config ${relayConfig}";
        Sockets = sockets;
        Environment = [ "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt" ];
        Restart = "on-failure";
        RestartSec = 5;
      };
      # Started at login rather than by the first connection, so the node is
      # up before an agent's first request.
      Install.WantedBy = [ "default.target" ];
    };
  };
}
