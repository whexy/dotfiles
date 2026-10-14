{ pkgs, perSystem }:

# Deterministic core of the video-editing toolkit: EDL validation, frame
# math, generated DaVinci Resolve scripts, B-roll slot definitions, NVENC
# finalizing and verification. ffmpeg and `transcribe` are bound onto PATH.
# /usr/lib/wsl/lib carries WSL's libcuda/libnvidia-encode, which NVENC
# needs; the Nix build sandbox has no GPU, so tests drive the filter graph
# with a software encoder instead.
let
  python = pkgs.python3.withPackages (ps: [
    ps.pillow
    ps.numpy
  ]);
  font = "${pkgs.noto-fonts-cjk-sans}/share/fonts/opentype/noto-cjk/NotoSansCJK-VF.otf.ttc";
in
pkgs.stdenvNoCC.mkDerivation {
  pname = "video-edit";
  version = "1.0.0";
  src = ./.;

  nativeBuildInputs = [ pkgs.makeWrapper ];
  nativeCheckInputs = [
    python
    pkgs.ffmpeg
  ];
  doCheck = true;
  checkPhase = ''
    runHook preCheck
    VIDEO_EDIT_FONT=${font} python3 -m unittest discover -s tests -t . -v
    runHook postCheck
  '';
  installPhase = ''
    runHook preInstall
    mkdir -p $out/lib/video-edit
    cp -r main.py video_edit style $out/lib/video-edit/
    makeWrapper ${python}/bin/python3 $out/bin/video-edit \
      --add-flags "$out/lib/video-edit/main.py" \
      --prefix PATH : ${
        pkgs.lib.makeBinPath [
          pkgs.ffmpeg
          perSystem.self.transcribe
        ]
      } \
      --prefix LD_LIBRARY_PATH : /usr/lib/wsl/lib \
      --set-default VIDEO_EDIT_FONT ${font}
    runHook postInstall
  '';

  meta = {
    description = "Frame-exact Resolve timeline builds, B-roll slots and checks for agent-driven video editing";
    mainProgram = "video-edit";
    platforms = pkgs.lib.platforms.linux;
  };
}
