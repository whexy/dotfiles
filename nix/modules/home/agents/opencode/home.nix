{
  pkgs,
  config,
  lib,
  apiAccounts,
  proxyAccounts,
}:
let
  settings = import ./config.nix {
    inherit
      config
      lib
      apiAccounts
      proxyAccounts
      ;
  };
in
{
  inherit settings;
  tui = import ./tui.nix;
  package = pkgs.llm-agents.opencode2;
  shellAliases.oc = "opencode2";
  homeFiles = import ./files.nix {
    inherit
      config
      lib
      proxyAccounts
      ;
    baseURL = settings.provider.ai-proxy.options.baseURL or null;
  };
}
