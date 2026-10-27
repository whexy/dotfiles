{ pkgs, perSystem }:

# Deterministic core of the video-editing toolkit: EDL validation, frame
# math, generated DaVinci Resolve scripts, B-roll slot definitions, GPU
# finalizing (NVENC on WSL, VideoToolbox on macOS) and verification. ffmpeg
# is bound onto PATH. `transcribe` is only a fallback after the caller's
# PATH, where the agents module installs the wrapper that supplies its API
# key.
let
  inherit (pkgs) lib;
  python = pkgs.python3.withPackages (ps: [
    ps.pillow
    ps.numpy
  ]);
  font = "${pkgs.noto-fonts-cjk-sans}/share/fonts/opentype/noto-cjk/NotoSansCJK-VF.otf.ttc";
  # WSL's libcuda and libnvidia-encode, which NVENC needs.
  wslArgs = lib.optionals pkgs.stdenv.hostPlatform.isLinux [
    "--prefix"
    "LD_LIBRARY_PATH"
    ":"
    "/usr/lib/wsl/lib"
  ];
in
pkgs.stdenvNoCC.mkDerivation {
  pname = "video-edit";
  version = "1.0.0";
  src = ./.;

  nativeBuildInputs = [ pkgs.makeWrapper ];
  installPhase = ''
    runHook preInstall
    mkdir -p $out/lib/video-edit
    cp -r main.py video_edit style $out/lib/video-edit/
    makeWrapper ${python}/bin/python3 $out/bin/video-edit \
      --add-flags "$out/lib/video-edit/main.py" \
      --prefix PATH : ${lib.makeBinPath [ pkgs.ffmpeg ]} \
      --suffix PATH : ${lib.makeBinPath [ perSystem.self.transcribe ]} \
      --set-default VIDEO_EDIT_FONT ${font} ${lib.escapeShellArgs wslArgs}
    runHook postInstall
  '';

  meta = {
    description = "Frame-exact Resolve timeline builds, B-roll slots and checks for agent-driven video editing";
    mainProgram = "video-edit";
    platforms = lib.platforms.linux ++ lib.platforms.darwin;
  };
}
