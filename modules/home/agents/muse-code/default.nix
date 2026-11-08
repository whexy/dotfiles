{
  config,
  lib,
  perSystem,
  ...
}:
{
  config = lib.mkIf config.dotfiles.agents.enable {
    dotfiles.agents.harnesses.muse = {
      package = perSystem.self.muse-code;
      rules.file = ".config/muse/AGENTS.md";
      skillsRoot = ".config/muse/skills";
      # Every host starts on the gateway: activation's first sync saves the
      # default entry and its credentials, so no host signs in to Meta.
      settings = {
        entries = import ./models.nix { inherit (config.dotfiles) llmGateways; };
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
      };
    };
  };
}
