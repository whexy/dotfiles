{ pkgs }:

# Agent-facing transcription CLI: gpt-transcribe for the words, whisper-1
# for word timestamps, aligned and annotated (pauses, fillers, stumbles)
# so an agent can propose video cuts from the transcript. ffmpeg is bound
# onto PATH because the tool shells out to it for probing, extraction,
# chunking, and silence detection, and not every host has it installed.
pkgs.stdenvNoCC.mkDerivation {
  pname = "transcribe";
  version = "1.0.0";
  src = ./.;

  nativeBuildInputs = [ pkgs.makeWrapper ];
  nativeCheckInputs = [ pkgs.python3 ];
  doCheck = true;
  checkPhase = ''
    runHook preCheck
    python3 -m unittest -v
    runHook postCheck
  '';
  installPhase = ''
    runHook preInstall
    install -Dm644 transcribe.py $out/lib/transcribe/transcribe.py
    makeWrapper ${pkgs.python3}/bin/python3 $out/bin/transcribe \
      --add-flags "$out/lib/transcribe/transcribe.py" \
      --prefix PATH : ${pkgs.lib.makeBinPath [ pkgs.ffmpeg ]}
    runHook postInstall
  '';

  meta = {
    description = "Word-timed, pause/stumble-annotated transcripts for agent-driven video cutting";
    mainProgram = "transcribe";
    platforms = pkgs.lib.platforms.unix;
  };
}
