{
  pkgs,
  config,
  lib,
  apiAccounts,
  proxyAccounts,
  proxy,
  withModelPicker,
}:
{
  packages = [
    (withModelPicker {
      name = "claude";
      package = pkgs.llm-agents.claude-code;
      entries = import ./models.nix {
        inherit
          config
          lib
          apiAccounts
          proxyAccounts
          proxy
          ;
      };
    })
  ];
  homeFiles.".claude/settings.json".source = ./settings.json;
}
