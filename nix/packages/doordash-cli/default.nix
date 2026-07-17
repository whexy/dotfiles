{
  pkgs,
  ...
}:

pkgs.stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "doordash-cli";
  version = "0.2.0";

  src = pkgs.fetchurl {
    url = "https://github.com/doordash-oss/doordash-cli/releases/download/v${finalAttrs.version}/dd-cli-v${finalAttrs.version}-darwin-arm64.tar.gz";
    hash = "sha256-zWUCwXBNErfX6bZNxY/afvrBp3Zafg64hyYPen3MZEI=";
  };

  sourceRoot = "dd-cli-v${finalAttrs.version}-darwin-arm64";

  installPhase = ''
    runHook preInstall
    install -Dm755 dd-cli-v${finalAttrs.version}-darwin-arm64 $out/bin/dd-cli
    runHook postInstall
  '';

  meta = with pkgs.lib; {
    description = "Terminal tool for ordering from DoorDash";
    longDescription = ''
      DoorDash CLI (dd-cli) is a terminal tool for ordering from DoorDash:
      search restaurants and stores, browse menus, build a cart, reorder a
      past order, and preview or check out, all from the command line.
    '';
    homepage = "https://github.com/doordash-oss/doordash-cli";
    downloadPage = "https://github.com/doordash-oss/doordash-cli/releases";
    license = licenses.unfree;
    mainProgram = "dd-cli";
    platforms = [ "aarch64-darwin" ];
    sourceProvenance = [ sourceTypes.binaryNativeCode ];
  };
})
