{
  config,
  lib,
  pkgs,
  perSystem,
  ...
}:
let
  cfg = config.dotfiles.agents;
  withModelPicker = import ../launcher/with-model-picker.nix {
    inherit pkgs;
    agentSettings = perSystem.self.agent-settings;
  };

  agent = withModelPicker {
    name = "muse";
    package = perSystem.self.muse-code;
    mcpServers = cfg.mcp.rendered.muse;
    inherit (cfg.launcher) prelude;
    managedLinks = [
      "AGENTS.md"
      "skills"
    ];
    maintainedSettings = {
      schema_version = 1;
    };
    resetEnv = [
      "META_API_KEY"
      "MUSE_CUSTOM_HEADERS"
      "MUSE_MODEL"
    ];
    entries = import ./models.nix { llmGateways = config.dotfiles.llmGateways; };
  };
in
{
  config = lib.mkIf cfg.enable {
    home = {
      packages = [ agent ];

      file.".config/muse/AGENTS.md".text = builtins.readFile ../global-rules.md;

      # Every host starts on the gateway: the first sync saves the default entry
      # and its credentials, so no host signs in to Meta.
      activation.museSettings = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
        run ${agent}/bin/muse-settings-sync
      '';
    };
  };
}
