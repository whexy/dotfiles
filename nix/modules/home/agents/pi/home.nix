{
  pkgs,
  config,
  lib,
  apiAccounts,
  proxyAccounts,
}:
let
  settings = import ./settings.nix {
    inherit
      pkgs
      lib
      apiAccounts
      proxyAccounts
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
  webSearch = import ./web-search.nix { inherit proxyAccounts; };
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
      + (
        if proxyAccounts then
          builtins.readFile ./DELEGATION_TIER_A.md
        else
          builtins.readFile ./DELEGATION_TIER_B.md
      );
    ".pi/agent/settings.json".text = builtins.toJSON settings;
    ".pi/agent/models.json".text = builtins.toJSON models;
    ".pi/agent/spending-guard.json".text = builtins.toJSON { enabled = false; };
    ".pi/web-search.json".text = builtins.toJSON webSearch;
    # Desktop notification on agent settle (see extensions/notify.ts).
    ".pi/agent/extensions/notify.ts".source = ./extensions/notify.ts;
  }
  // lib.optionalAttrs proxyAccounts {
    # Discover the proxy catalog and clone matching model metadata from pi.
    ".pi/agent/extensions/ai-proxy.ts".source = ./ai-proxy.ts;
  };
}
