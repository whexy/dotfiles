# AI coding agents configuration
{
  pkgs,
  config,
  lib,
  ...
}:
let
  opencode_settings = import ./opencode/config.nix { inherit config lib; };
  opencode_tui = import ./opencode/tui.nix;
  pi_settings = import ./pi/settings.nix { inherit config lib; };
  pi_models = import ./pi/models.nix { inherit config pkgs lib; };

  # claude_code_config = builtins.readFile ./claude-code/settings.json;
  # claude_code_settings = builtins.fromJSON claude_code_config;
in
{
  home = {
    file = {
      # Deploy the notification plugin so it is auto-loaded by OpenCode.
      ".config/opencode/plugins/notify.js".source = ./opencode/plugins/notify.js;
      ".pi/agent/settings.json".text = builtins.toJSON pi_settings;
      ".pi/agent/models.json".text = builtins.toJSON pi_models;
    };

    packages = [ pkgs.llm-agents.pi ];

    shellAliases = {
      oc = "opencode";
    };
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
