{ pkgs, flake }:

# Wakaru: JavaScript decompiler and unpacker, which REA drives to recover
# modules from bundles. Upstream ships prebuilt Linux binaries only.
let
  inherit (pkgs) lib stdenv;
  sources = lib.importJSON ./sources.json;
  platforms = {
    x86_64-linux = "linux-x64";
    aarch64-linux = "linux-arm64";
  };
  urlTemplate = "https://github.com/pionxzh/wakaru/releases/download/v{version}/wakaru-{platform}.tar.gz";
  binary = flake.lib.platformBinary {
    inherit
      pkgs
      sources
      urlTemplate
      platforms
      ;
  };
in
stdenv.mkDerivation (finalAttrs: {
  pname = "wakaru";
  inherit (sources) version;

  inherit (binary) src;
  sourceRoot = ".";

  nativeBuildInputs = [ pkgs.autoPatchelfHook ];
  buildInputs = [ stdenv.cc.cc.lib ];

  installPhase = ''
    runHook preInstall
    install -Dm755 wakaru $out/bin/wakaru
    runHook postInstall
  '';

  passthru.updater = flake.lib.updater {
    kind = "platform-binaries";
    versionSource = {
      type = "github";
      owner = "pionxzh";
      repo = "wakaru";
    };
    inherit urlTemplate platforms;
  };

  meta = {
    description = "JavaScript decompiler and unpacker for bundled code";
    homepage = "https://github.com/pionxzh/wakaru";
    changelog = "https://github.com/pionxzh/wakaru/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.mit;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    mainProgram = "wakaru";
    platforms = binary.metaPlatforms;
  };
})
