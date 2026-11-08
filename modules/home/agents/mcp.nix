# MCP servers every agent registers. A feature adds its server to
# `dotfiles.agents.mcp.servers`, and each agent takes the set in its own
# config's shape from `dotfiles.agents.mcp.rendered`: no two agents read the
# same one.
args@{ config, lib, ... }:
let
  cfg = config.dotfiles.agents;
  relay = config.dotfiles.tailnetRelay;
  tldraw = "https://draw.at-basking.ts.net";

  server = lib.types.submodule {
    options = {
      url = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Endpoint of a remote server, spoken to over streamable HTTP.";
      };
      headers = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
        description = "HTTP headers sent to a remote server.";
      };
      command = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Executable of a local server, spoken to over stdio.";
      };
      args = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Arguments of a local server's command.";
      };
      env = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
        description = "Environment of a local server.";
      };
    };
  };

  optional = name: value: lib.optionalAttrs (value != { } && value != [ ]) { ${name} = value; };
  remote = s: s.url != null;

  formats = {
    # Claude names the transport of a remote server only.
    claude =
      s:
      if remote s then
        {
          type = "http";
          inherit (s) url;
        }
        // optional "headers" s.headers
      else
        { inherit (s) command; } // optional "args" s.args // optional "env" s.env;

    # Codex tells the transports apart by `url` versus `command`.
    codex =
      s:
      if remote s then
        { inherit (s) url; } // optional "http_headers" s.headers
      else
        { inherit (s) command; } // optional "args" s.args // optional "env" s.env;

    # Muse expands `${VAR}` in header values, like Claude.
    muse =
      s:
      if remote s then
        {
          transport = "streamable_http";
          inherit (s) url;
        }
        // optional "headers" s.headers
      else
        {
          transport = "stdio";
          inherit (s) command args;
        }
        // optional "env" s.env;

    opencode =
      s:
      if remote s then
        {
          type = "remote";
          inherit (s) url;
        }
        // optional "headers" s.headers
      else
        {
          type = "local";
          command = [ s.command ] ++ s.args;
        }
        // optional "environment" s.env;
  };
in
{
  options.dotfiles.agents = {
    mcp.servers = lib.mkOption {
      type = lib.types.attrsOf server;
      default = { };
      description = "MCP servers by name: `url` for a remote server, `command` for a local one.";
    };

    mcp.rendered = lib.mkOption {
      type = lib.types.attrsOf (lib.types.attrsOf lib.types.anything);
      readOnly = true;
      default = lib.mapAttrs (_: render: lib.mapAttrs (_: render) cfg.mcp.servers) formats;
      defaultText = lib.literalMD "`servers` in each agent's shape";
      description = "`servers` in the shape each agent's config takes, keyed by agent.";
    };

    tldraw.enable = lib.mkOption {
      type = lib.types.bool;
      # The server only resolves on the tailnet, so registering it elsewhere
      # leaves every agent with a permanently failing MCP server. Standalone
      # homes have no osConfig to say whether this machine is on the tailnet,
      # but a home with a tailnet relay reaches it through that.
      default = args.osConfig.dotfiles.network.tailscale.enable or relay.enable;
      defaultText = lib.literalExpression "osConfig.dotfiles.network.tailscale.enable or config.dotfiles.tailnetRelay.enable";
      description = "Whether to register the tailnet tldraw MCP server (draw.at-basking.ts.net).";
    };
  };

  # Live tldraw whiteboard rooms; agents read and draw diagrams that broadcast
  # to anyone viewing the room. Unauthenticated: reachability is the only
  # access control, which is why registration follows tailscale.
  config = lib.mkMerge [
    {
      assertions = lib.mapAttrsToList (name: s: {
        assertion = (s.url == null) != (s.command == null);
        message = "dotfiles.agents.mcp.servers.${name} must set exactly one of url and command.";
      }) cfg.mcp.servers;
    }
    (lib.mkIf (cfg.enable && cfg.tldraw.enable) (
      lib.mkMerge [
        {
          dotfiles.agents.mcp.servers.tldraw.url = "${
            if relay.enable then relay.forwards.tldraw.url else tldraw
          }/mcp";
        }
        (lib.mkIf relay.enable {
          dotfiles.tailnetRelay.forwards.tldraw = {
            port = 47305;
            upstream = tldraw;
          };
          dotfiles.agents.launcher.relayListeners = [ relay.forwards.tldraw.address ];
        })
      ]
    ))
  ];
}
