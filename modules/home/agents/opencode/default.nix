{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.dotfiles.agents;
  upstream = pkgs.llm-agents.opencode2;
  # The package installs its binary as `opencode2` to coexist with v1.
  #
  # The shared background server inherits the environment of the launch that
  # starts it, so it keeps that launch's prelude until `opencode service
  # restart`.
  package = pkgs.writeShellScriptBin "opencode" ''
    ${cfg.launcher.prelude}
    exec ${lib.getExe' upstream "opencode2"} "$@"
  '';
  settings = import ./config.nix {
    inherit pkgs lib;
    inherit (cfg.opencode) model smallModel;
    inherit (config.dotfiles.llmGateways) gateways;
    access = config.dotfiles.cloudflareAccess.serviceToken;
    mcpServers = cfg.mcp.servers;
  };
in
{
  # A gateway's provider ID prefixes the model; magpie serves the Claude
  # subscription as its `claude` provider, as in `magpie/claude/claude-opus-5-5`.
  options.dotfiles.agents.opencode = {
    model = lib.mkOption {
      type = lib.types.str;
      default = "cliproxyapi/claude-opus-5-5";
      description = "Model OpenCode uses unless told otherwise, as `<gateway>/<model>`.";
    };
    smallModel = lib.mkOption {
      type = lib.types.str;
      default = "cliproxyapi/claude-sonnet-5-5";
      description = "Model for OpenCode's small tasks, such as session titles, as `<gateway>/<model>`.";
    };
  };

  config = lib.mkIf cfg.enable {
    home = {
      packages = [ package ];
      shellAliases.oc = "opencode";
      file.".config/opencode/opencode.json".text = builtins.toJSON settings;
      file.".config/opencode/AGENTS.md".source = ../global-rules.md;
    };
  };
}
