{ pkgs }:

# WeType-style dictation for fcitx5: F19 streams the microphone to
# wetype-asr and shows the text as preedit while the user speaks; F19 again
# commits the polished transcript.
let
  inherit (pkgs) lib;
  python = pkgs.python3.withPackages (ps: [ ps.websockets ]);
in
pkgs.stdenv.mkDerivation {
  pname = "wetype-dictate";
  version = "0.1.0";
  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.difference ./. ./default.nix;
  };

  nativeBuildInputs = [
    pkgs.cmake
    pkgs.makeWrapper
  ];
  buildInputs = [ pkgs.fcitx5 ];

  doCheck = true;

  postInstall = ''
    install -Dm644 $src/wetype_dictate.py $out/lib/wetype-dictate/wetype_dictate.py
    makeWrapper ${lib.getExe python} $out/libexec/wetype-dictate \
      --add-flags "-I $out/lib/wetype-dictate/wetype_dictate.py" \
      --prefix PATH : ${lib.makeBinPath [ pkgs.pipewire ]} \
      --set-default SSL_CERT_FILE ${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt
  '';

  meta = {
    description = "Dictation on one key for fcitx5, through wetype-asr";
    platforms = lib.platforms.linux;
  };
}
