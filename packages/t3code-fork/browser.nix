# The Chrome for Testing headless shell T3's preview tools download into
# `~/.t3/tools/chrome-headless-shell/<platform>/<version>` on first use; it
# cannot find its libraries on NixOS. T3 skips the download when an executable
# already sits there, so Home Manager links this patched copy in. Darwin keeps
# T3's own download, which runs as is.
#
# The pin is read from the server source this package builds, so the browser
# always matches the server without a pin of its own.
{
  pkgs,
  source,
}:
let
  inherit (pkgs) lib;
  file = "${source}/apps/server/src/preview/PreviewBrowser.ts";
  lines = lib.splitString "\n" (builtins.readFile file);
  matchLine =
    regex: from:
    let
      matches = lib.filter (m: m != null) (map (builtins.match regex) (lib.drop from lines));
    in
    if matches == [ ] then
      throw "t3code-fork: no line matching ${regex} in ${file}"
    else
      lib.head matches;
  lineIndex =
    regex:
    lib.lists.findFirstIndex (
      line: builtins.match regex line != null
    ) (throw "t3code-fork: no line matching ${regex} in ${file}") lines;

  version = lib.head (matchLine ''const VERSION = "([^"]+)";'' 0);
  platform =
    {
      aarch64-linux = "linux-arm64";
      x86_64-linux = "linux64";
    }
    .${pkgs.stdenv.hostPlatform.system};
  hex = lib.head (
    matchLine ''[[:space:]]*sha256: "([0-9a-f]{64})",'' (lineIndex ''[[:space:]]*"?${platform}"?: \{'')
  );
in
pkgs.stdenvNoCC.mkDerivation {
  pname = "t3code-chrome-headless-shell";
  inherit version;

  passthru = { inherit platform; };

  src = pkgs.fetchurl {
    url = "https://storage.googleapis.com/chrome-for-testing-public/${version}/${platform}/chrome-headless-shell-${platform}.zip";
    hash = builtins.convertHash {
      hash = hex;
      hashAlgo = "sha256";
      toHashFormat = "sri";
    };
  };

  sourceRoot = "chrome-headless-shell-${platform}";

  nativeBuildInputs = [
    pkgs.autoPatchelfHook
    pkgs.unzip
  ];

  buildInputs = with pkgs; [
    alsa-lib
    at-spi2-core
    atk
    dbus
    expat
    glib
    libgbm
    libx11
    libxcb
    libxcomposite
    libxdamage
    libxext
    libxfixes
    libxkbcommon
    libxrandr
    nspr
    nss
    stdenv.cc.cc.lib
    udev
  ];

  dontStrip = true;

  installPhase = ''
    runHook preInstall
    cp -R . "$out"
    runHook postInstall
  '';

  meta = {
    description = "Chrome for Testing headless shell pinned by T3 Code";
    homepage = "https://googlechromelabs.github.io/chrome-for-testing/";
    license = lib.licenses.bsd3;
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
}
