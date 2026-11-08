# MCP servers every agent registers. A feature adds its server to
# `dotfiles.agents.mcp.servers`, and each agent takes the set in its own
# config's shape from `dotfiles.agents.mcp.rendered`: no two agents read the
# same one.
{ config, lib, ... }:
let
  cfg = config.dotfiles.agents;

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
  };

  config.assertions = lib.mapAttrsToList (name: s: {
    assertion = (s.url == null) != (s.command == null);
    message = "dotfiles.agents.mcp.servers.${name} must set exactly one of url and command.";
  }) cfg.mcp.servers;
}
