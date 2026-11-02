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
      (pkgs.writeShellScriptBin "transcribe" ''
        if secret=$(${pkgs.coreutils}/bin/cat "${config.age.secrets.openai-api-key.path}" 2>/dev/null); then
          export OPENAI_API_KEY="$secret"
        fi
        exec ${lib.getExe perSystem.self.transcribe} "$@"
      '')
    ];
    # whisper-1 for `transcribe`; a key restricted to the Audio API.
    age.secrets.openai-api-key.file = ../../../../secrets/openai-api-key.age;
    dotfiles.agents.skills = import ./skills.nix { inherit pkgs perSystem; };
  };
}
