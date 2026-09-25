{
  pkgs,
  config,
  lib,
  apiAccounts,
  proxyAccounts,
  proxy,
  defaults,
  mcp,
  models,
}:
let
  aiProxyExtension = import ./ai-proxy.nix { inherit pkgs proxy; };
  settings = import ./settings.nix {
    inherit
      pkgs
      lib
      config
      proxyAccounts
      aiProxyExtension
      defaults
      mcp
      models
      ;
  };
  providers = import ./models.nix {
    inherit
      config
      pkgs
      lib
      apiAccounts
      ;
  };
  webSearch = import ./web-search.nix { inherit defaults; };

  # Delegation policy is a skill, not prompt text: it only applies once the
  # agent is already about to launch a subagent, and AGENTS.md keeps the gate
  # that sends it here. The roster half depends on which providers this host
  # has, so the file is assembled rather than symlinked, which also keeps it
  # out of ../skills (one store symlink shared with codex and claude, neither
  # of which has a subagent tool).
  delegationPolicy = pkgs.writeText "delegation-policy-SKILL.md" (
    builtins.readFile ./skills/delegation-policy/SKILL_BASE.md
    + "\n"
    + (
      if proxyAccounts then
        builtins.readFile ./skills/delegation-policy/ROSTER_TIER_A.md
      else
        builtins.readFile ./skills/delegation-policy/ROSTER_TIER_B.md
    )
  );
in
{
  # Extension install scripts invoke node through PATH, even with an absolute npmCommand.
  packages = [
    pkgs.llm-agents.pi
    pkgs.nodejs
  ];
  homeFiles = {
    # Shared global rules plus the pi-only `whoami` mechanism. Other agents
    # consume the plain AGENTS.md.
    ".pi/agent/AGENTS.md".text =
      builtins.readFile ../AGENTS.md + "\n" + builtins.readFile ./SPECIAL_INSTRUCTION.md;
    ".pi/agent/skills/delegation-policy/SKILL.md".source = delegationPolicy;
    ".pi/agent/settings.json".text = builtins.toJSON settings;
    ".pi/agent/models.json".text = builtins.toJSON providers;
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
