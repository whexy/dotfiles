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
      name = "codex";
      package = pkgs.llm-agents.codex;
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
}
