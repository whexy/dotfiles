{
  pkgs,
}:

let
  inherit (pkgs) lib;
  metadata = import ./metadata.nix;
  platform =
    {
      aarch64-darwin = "darwin-arm64";
      aarch64-linux = "linux-arm64";
      x86_64-linux = "linux-x64";
    }
    .${pkgs.stdenv.hostPlatform.system}
      or (throw "t3code-nightly: unsupported system ${pkgs.stdenv.hostPlatform.system}");
in
pkgs.stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "t3code-nightly";
  inherit (metadata) version;

  src = pkgs.fetchurl {
    url = "https://registry.npmjs.org/@t3code/t3-${platform}/-/t3-${platform}-${finalAttrs.version}.tgz";
    hash = metadata.hashes.${platform};
  };

  sourceRoot = "package";

  nativeBuildInputs = lib.optionals pkgs.stdenv.hostPlatform.isLinux [
    pkgs.autoPatchelfHook
  ];

  buildInputs = lib.optionals pkgs.stdenv.hostPlatform.isLinux [
    pkgs.glibc
    pkgs.stdenv.cc.cc.lib
  ];

  # The executable is a Node single-executable with an embedded runtime
  # payload; stripping it removes data that the runtime needs at startup.
  dontStrip = true;

  unpackPhase = ''
    runHook preUnpack
    tar -xzf "$src"
    runHook postUnpack
  '';

  installPhase = ''
    runHook preInstall
    install -d "$out/bin" "$out/libexec/t3code"
    cp -R . "$out/libexec/t3code/"
    ln -s ../libexec/t3code/t3 "$out/bin/t3"
    runHook postInstall
  '';

  nativeInstallCheckInputs = [ pkgs.versionCheckHook ];
  doInstallCheck = true;
  versionCheckProgram = "${placeholder "out"}/bin/t3";
  versionCheckProgramArg = [ "--version" ];

  meta = {
    description = "Nightly T3 Code server";
    homepage = "https://t3.codes";
    changelog = "https://github.com/pingdotgg/t3code/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.mit;
    mainProgram = "t3";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
      "aarch64-darwin"
    ];
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
})
