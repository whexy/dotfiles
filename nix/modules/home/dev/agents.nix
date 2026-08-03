# AI coding agents configuration
{
  pkgs,
  config,
  ...
}:
let
  opencode_settings = import ./opencode/config.nix { inherit config; };
  opencode_tui = import ./opencode/tui.nix;

  # claude_code_config = builtins.readFile ./claude-code/settings.json;
  # claude_code_settings = builtins.fromJSON claude_code_config;
in
{
  # Deploy the OpenCode notification plugin so it is auto-loaded by OpenCode.
  home.file.".config/opencode/plugins/notify.js".source = ./opencode/plugins/notify.js;

  home.shellAliases = {
    oc = "opencode";
  };

  age = {
    secrets = {
      openai-api-key = {
        file = ../../../../secrets/openai-api-key.age;
        path = "${config.home.homeDirectory}/.secrets/openai-api-key";
      };
      anthropic-api-key = {
        file = ../../../../secrets/anthropic-api-key.age;
        path = "${config.home.homeDirectory}/.secrets/anthropic-api-key";
      };
      deepseek-api-key = {
        file = ../../../../secrets/deepseek-api-key.age;
        path = "${config.home.homeDirectory}/.secrets/deepseek-api-key";
      };
    };
  };

  programs = {
    opencode = {
      enable = true;
      package = pkgs.llm-agents.opencode;
      settings = opencode_settings;
      tui = opencode_tui;
    };
  };
}
