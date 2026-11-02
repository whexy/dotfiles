# MCP servers every agent registers. A feature adds its server to
# `dotfiles.agents.mcp.servers`; each agent renders the set into its own
# config format (JSON for claude and opencode, inline TOML for codex),
# because no two of them read the same file.
args@{ config, lib, ... }:
let
  cfg = config.dotfiles.agents;
in
{
  options.dotfiles.agents = {
    mcp.servers = lib.mkOption {
      type = lib.types.attrsOf (lib.types.attrsOf lib.types.anything);
      default = { };
      description = ''
        MCP servers by name, in Claude's shape: `url` for a remote server,
        `command` plus `args` and `env` for a local one. `type` is Claude's
        discriminator for a remote server; the other agents select the
        transport by `url`.
      '';
    };

    tldraw.enable = lib.mkOption {
      type = lib.types.bool;
      # The server only resolves on the tailnet, so registering it elsewhere
      # leaves every agent with a permanently failing MCP server. Standalone
      # homes have no osConfig to say whether this machine is on the tailnet.
      default = args.osConfig.dotfiles.network.tailscale.enable or false;
      defaultText = lib.literalExpression "osConfig.dotfiles.network.tailscale.enable or false";
      description = "Whether to register the tailnet tldraw MCP server (draw.at-basking.ts.net).";
    };
  };

  # Live tldraw whiteboard rooms; agents read and draw diagrams that broadcast
  # to anyone viewing the room. Unauthenticated: reachability is the only
  # access control, which is why registration follows tailscale.
  config = lib.mkIf (cfg.enable && cfg.tldraw.enable) {
    dotfiles.agents.mcp.servers.tldraw = {
      type = "http";
      url = "https://draw.at-basking.ts.net/mcp";
    };
  };
}
