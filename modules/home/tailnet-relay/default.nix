# A userspace tailnet node for hosts that run no Tailscale daemon, such as
# shared servers: it relays loopback connections to tailnet services, and
# only from processes of this home's user (packages/tailnet-relay). HTTP
# forwards serve clients that take a base URL; a SOCKS5 proxy serves the
# rest.
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
  # What each socket unit listens on, by the name the relay knows it by.
  listeners =
    lib.mapAttrs (_: forward: {
      inherit (forward) address;
      description = "Tailnet relay to ${forward.upstream}";
    }) cfg.forwards
    // {
      proxy = {
        inherit (cfg.proxy) address;
        description = "Tailnet relay's SOCKS5 proxy";
      };
    };
  sockets = map (name: "${socketUnit name}.socket") (lib.attrNames listeners);

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
      proxy = cfg.proxy.address;
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

    proxy = {
      port = lib.mkOption {
        type = lib.types.port;
        default = 47300;
        description = ''
          Loopback port of the relay's SOCKS5 proxy, which connects to any
          tailnet address the node's tags reach. Clients whose protocol does
          not authenticate the far end run `checker` on its address first;
          `connect` does for ssh.
        '';
      };
      address = lib.mkOption {
        type = lib.types.str;
        readOnly = true;
        default = "127.0.0.1:${toString cfg.proxy.port}";
        description = "Address SOCKS5 clients connect to.";
      };
      url = lib.mkOption {
        type = lib.types.str;
        readOnly = true;
        default = "socks5://${cfg.proxy.address}";
        description = "The proxy as a URL, such as a kubeconfig's `proxy-url`.";
      };
    };

    connect = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = "${lib.getExe' perSystem.self.tailnet-relay "tailnet-relay-connect"} ${cfg.proxy.address}";
      defaultText = lib.literalMD "`tailnet-relay-connect` of `packages/tailnet-relay`, with the proxy's address";
      description = ''
        Command that connects standard input and output to the host and port
        it is given, through the proxy, after `checker`'s test of the proxy:
        an ssh `ProxyCommand` when followed by `%h %p`.
      '';
    };

    checker = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = lib.getExe' perSystem.self.tailnet-relay "tailnet-relay-check";
      defaultText = lib.literalMD "`tailnet-relay-check` of `packages/tailnet-relay`";
      description = ''
        Command that exits non-zero unless this user holds every forward or
        proxy address it is given. Any port is free for another user to take while
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
        assertion = !(cfg.forwards ? proxy);
        message = "dotfiles.tailnetRelay.forwards.proxy is the name of the relay's proxy.";
      }
      {
        assertion = lib.allUnique (
          [ cfg.proxy.port ] ++ lib.mapAttrsToList (_: forward: forward.port) cfg.forwards
        );
        message = "dotfiles.tailnetRelay's forwards and proxy share a port.";
      }
    ];

    age.secrets.tailnet-relay-oauth.file = ../../../secrets/tailnet-relay-oauth.age;

    # systemd holds each port, so it stays this user's while the relay
    # restarts; a port another user took first fails its socket unit.
    systemd.user.sockets = lib.mapAttrs' (
      name: listener:
      lib.nameValuePair (socketUnit name) {
        Unit.Description = listener.description;
        Socket = {
          ListenStream = listener.address;
          FileDescriptorName = name;
          Service = "tailnet-relay.service";
        };
        Install.WantedBy = [ "sockets.target" ];
      }
    ) listeners;

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
