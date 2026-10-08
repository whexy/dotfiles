{
  pkgs,
  lib,
  proxy,
  defaults,
  mcp,
}:
let
  aiProxyExtension = import ./ai-proxy.nix { inherit pkgs proxy; };
  settings = import ./settings.nix {
    inherit pkgs defaults;
  };
  webSearch = import ./web-search.nix { inherit defaults; };

in
{
  # Extension install scripts invoke node through PATH, even with an absolute npmCommand.
  packages = [
    pkgs.llm-agents.pi
    pkgs.nodejs
  ];
  homeFiles = {
    # Shared global rules plus the pi-only `whoami` mechanism.
    ".pi/agent/AGENTS.md".text =
      builtins.readFile ../AGENTS.md + "\n" + builtins.readFile ./SPECIAL_INSTRUCTION.md;
    ".pi/agent/settings.json".text = builtins.toJSON settings;
    ".pi/agent/spending-guard.json".text = builtins.toJSON { enabled = false; };
    ".pi/web-search.json".text = builtins.toJSON webSearch;
  }
  // lib.optionalAttrs (mcp.servers != { }) {
    ".pi/agent/mcp.json".text = builtins.toJSON { mcpServers = mcp.servers; };
  }
  // {
    # Desktop notification on agent settle (see extensions/notify.ts).
    ".pi/agent/extensions/notify.ts".source = ./extensions/notify.ts;
  }
  // {
    # Discover the CLIProxyAPI catalog and clone matching model metadata from pi.
    ".pi/agent/extensions/ai-proxy.ts".source = aiProxyExtension;
  };
}
