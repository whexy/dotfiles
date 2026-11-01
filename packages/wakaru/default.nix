{ pkgs, flake }:

# Wakaru: JavaScript decompiler and unpacker, which REA drives to recover
# modules from bundles. Upstream ships prebuilt Linux binaries only.
let
  inherit (pkgs) lib stdenv;
  inherit (stdenv.hostPlatform) system;
  sources = lib.importJSON ./sources.json;
  platforms = {
    x86_64-linux = "linux-x64";
    aarch64-linux = "linux-arm64";
  };
  platform = platforms.${system} or (throw "wakaru: no release binary for ${system}");
  urlTemplate = "https://github.com/pionxzh/wakaru/releases/download/v{version}/wakaru-{platform}.tar.gz";
in
stdenv.mkDerivation (finalAttrs: {
  pname = "wakaru";
  inherit (sources) version;

  src = pkgs.fetchurl {
    url =
      builtins.replaceStrings [ "{version}" "{platform}" ] [ finalAttrs.version platform ]
        urlTemplate;
    hash = sources.hashes.${system};
  };
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
    platforms = lib.attrNames sources.hashes;
  };
})
