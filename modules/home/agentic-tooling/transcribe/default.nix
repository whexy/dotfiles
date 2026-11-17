{
  config,
  lib,
  pkgs,
  perSystem,
  flake,
  ...
}:
let
  relay = config.dotfiles.tailnetRelay;
  cat = "${pkgs.coreutils}/bin/cat";
in
{
  config = lib.mkIf config.dotfiles.agenticTooling.transcribe.enable (
    lib.mkMerge [
      {
        # Each backend's key goes into the environment of this process
        # alone; the store and the agent that runs it never see it.
        home.packages = [
          (pkgs.writeShellScriptBin "transcribe" ''
            if secret=$(${cat} "${config.age.secrets.openai-api-key.path}" 2>/dev/null); then
              export OPENAI_API_KEY="$secret"
            fi
            if token=$(${cat} "${config.age.secrets.wetype-asr-transcribe-token.path}" 2>/dev/null); then
              export WETYPE_ASR_TOKEN="$token"
            fi
            ${lib.optionalString relay.enable ''
              # The token must not reach a listener another user put on the
              # forward's port; an empty URL tells transcribe there is no route.
              if ${relay.checker} ${relay.forwards.wetype-asr.address} 2>/dev/null; then
                export WETYPE_ASR_URL=${relay.forwards.wetype-asr.url}/v1
              else
                export WETYPE_ASR_URL=
              fi
            ''}
            exec ${lib.getExe perSystem.self.transcribe} "$@"
          '')
        ];
        # whisper-1, for word timing; a key restricted to the Audio API.
        age.secrets.openai-api-key.file = ../../../../secrets/openai-api-key.age;
        # wetype-asr, the default backend.
        age.secrets.wetype-asr-transcribe-token.file = ../../../../secrets/wetype-asr-transcribe-token.age;
        dotfiles.agents.skills = import ./skills.nix { inherit pkgs perSystem flake; };
      }
      (lib.mkIf relay.enable {
        dotfiles.tailnetRelay.forwards.wetype-asr = {
          port = 47307;
          upstream = "https://${flake.lib.tailnetHost "wetype-asr"}";
        };
      })
    ]
  );
}
