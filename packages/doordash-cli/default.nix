{
  pkgs,
  ...
}:

let
  platform =
    {
      aarch64-darwin = "darwin-arm64";
      x86_64-linux = "linux-amd64";
    }
    .${pkgs.stdenv.hostPlatform.system}
      or (throw "doordash-cli: unsupported system ${pkgs.stdenv.hostPlatform.system}");

  hashes = {
    darwin-arm64 = "sha256-TEZ81zquMZu9bZQOzta0gy2ZGThW6bAiFNXomJnM4A8=";
    linux-amd64 = "sha256-G+gDmI5Bo/Twk9+A4OpQZZQN2oNDxWUoTiax1aj9KJw=";
  };
in
pkgs.stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "doordash-cli";
  version = "0.2.2";

  src = pkgs.fetchurl {
    url = "https://github.com/doordash-oss/doordash-cli/releases/download/v${finalAttrs.version}/dd-cli-v${finalAttrs.version}-${platform}.tar.gz";
    hash = hashes.${platform};
  };

  sourceRoot = "dd-cli-v${finalAttrs.version}-${platform}";

  installPhase = ''
    runHook preInstall
    install -Dm755 dd-cli-v${finalAttrs.version}-${platform} $out/bin/dd-cli
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
    platforms = [
      "aarch64-darwin"
      "x86_64-linux"
    ];
    sourceProvenance = [ sourceTypes.binaryNativeCode ];
  };
})
