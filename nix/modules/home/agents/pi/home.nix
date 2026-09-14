{
  pkgs,
  config,
  lib,
  apiAccounts,
  proxyAccounts,
  proxy,
  defaults,
  mcp,
}:
let
  aiProxyExtension = import ./ai-proxy.nix { inherit pkgs proxy; };
  settings = import ./settings.nix {
    inherit
      pkgs
      lib
      config
      apiAccounts
      proxyAccounts
      aiProxyExtension
      defaults
      mcp
      ;
  };
  models = import ./models.nix {
    inherit
      config
      pkgs
      lib
      apiAccounts
      ;
  };
  webSearch = import ./web-search.nix { inherit defaults; };

  # A launch failure caches a 24h model exclusion that outlives its cause and
  # cannot be cleared from inside a running session, so a transient proxy or
  # config error blocks that model for the rest of the day. Five minutes still
  # absorbs a flapping provider without surviving the fix for it.
  subagentConfig = {
    modelExclusions.defaultTtlMs = 5 * 60 * 1000;
  };
in
{
  packages = [ pkgs.llm-agents.pi ];
  homeFiles = {
    # Shared global rules; pi-specific delegation guidance is tiered by
    # proxy availability (TIER A allows liberal subagent spawning on the
    # proxy, TIER B is conservative). Other agents consume the plain
    # AGENTS.md.
    ".pi/agent/AGENTS.md".text =
      builtins.readFile ../AGENTS.md
      + "\n"
      + builtins.readFile ./SPECIAL_INSTRUCTION.md
      + "\n"
      + (
        if proxyAccounts then
          builtins.readFile ./DELEGATION_TIER_A.md
        else
          builtins.readFile ./DELEGATION_TIER_B.md
      );
    ".pi/agent/settings.json".text = builtins.toJSON settings;
    ".pi/agent/extensions/subagent/config.json".text = builtins.toJSON subagentConfig;
    ".pi/agent/models.json".text = builtins.toJSON models;
    ".pi/agent/spending-guard.json".text = builtins.toJSON { enabled = false; };
    ".pi/web-search.json".text = builtins.toJSON webSearch;
  }
  // lib.optionalAttrs (mcp.servers != { }) {
    # pi has no built-in MCP client; pi-mcp-adapter (enabled in settings.nix)
    # reads this file and exposes one proxy tool the agent searches, instead
    # of loading every server's tool definitions into the context window.
    ".pi/agent/mcp.json".text = builtins.toJSON {
      mcpServers = mcp.servers;
      # The adapter's persistent footer line costs a screen row for state that
      # `/mcp status` reports on demand.
      settings.mcpFooterStatus = "off";
    };
  }
  // {
    # Desktop notification on agent settle (see extensions/notify.ts).
    ".pi/agent/extensions/notify.ts".source = ./extensions/notify.ts;
  }
  // lib.optionalAttrs proxyAccounts {
    # Discover the proxy catalog and clone matching model metadata from pi.
    ".pi/agent/extensions/ai-proxy.ts".source = aiProxyExtension;
  };
}
