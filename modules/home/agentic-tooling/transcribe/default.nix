{
  config,
  lib,
  pkgs,
  perSystem,
  ...
}:
{
  config = lib.mkIf config.dotfiles.agenticTooling.transcribe.enable {
    # whisper-1 needs an OpenAI key in the environment of this process
    # alone; the store and the agent that runs it never see the key.
    home.packages = [
      (config.dotfiles.onepassword.wrap {
        package = perSystem.self.transcribe;
        env.OPENAI_API_KEY = "openai-api-key";
      })
    ];
    dotfiles.agents.skills = import ./skills.nix { inherit pkgs perSystem; };
  };
}
