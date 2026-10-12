{ pkgs }:

# Wakaru: JavaScript decompiler and unpacker, which REA drives to recover
# modules from bundles. Upstream ships prebuilt Linux binaries only.
let
  inherit (pkgs) lib stdenv;
  version = "1.14.0";
  assets = {
    x86_64-linux = {
      name = "wakaru-linux-x64.tar.gz";
      hash = "sha256-2w5iADRyMZWrQm6U0A1V29j9AQapKK2iVj8RAxltCfo=";
    };
    aarch64-linux = {
      name = "wakaru-linux-arm64.tar.gz";
      hash = "sha256-coRWs6W4z0HHCwA8gWEkI1/+RpTZ7sYutONblJQzV6Q=";
    };
  };
  asset =
    assets.${stdenv.hostPlatform.system}
      or (throw "wakaru: no release binary for ${stdenv.hostPlatform.system}");
in
stdenv.mkDerivation {
  pname = "wakaru";
  inherit version;

  src = pkgs.fetchurl {
    url = "https://github.com/pionxzh/wakaru/releases/download/v${version}/${asset.name}";
    inherit (asset) hash;
  };
  sourceRoot = ".";

  nativeBuildInputs = [ pkgs.autoPatchelfHook ];
  buildInputs = [ stdenv.cc.cc.lib ];

  installPhase = ''
    runHook preInstall
    install -Dm755 wakaru $out/bin/wakaru
    runHook postInstall
  '';

  meta = {
    description = "JavaScript decompiler and unpacker for bundled code";
    homepage = "https://github.com/pionxzh/wakaru";
    license = lib.licenses.mit;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    mainProgram = "wakaru";
    platforms = lib.attrNames assets;
  };
}
