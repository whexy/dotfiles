{
  pkgs,
  flake,
  ...
}:

let
  inherit (pkgs) lib;
  inherit (pkgs.stdenv.hostPlatform) system;
  sources = lib.importJSON ./sources.json;
  platforms = {
    aarch64-darwin = "darwin-arm64";
    x86_64-linux = "linux-amd64";
  };
  platform = platforms.${system} or (throw "doordash-cli: unsupported system ${system}");
  urlTemplate = "https://github.com/doordash-oss/doordash-cli/releases/download/v{version}/dd-cli-v{version}-{platform}.tar.gz";
in
pkgs.stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "doordash-cli";
  inherit (sources) version;

  src = pkgs.fetchurl {
    url =
      builtins.replaceStrings [ "{version}" "{platform}" ] [ finalAttrs.version platform ]
        urlTemplate;
    hash = sources.hashes.${system};
  };

  sourceRoot = "dd-cli-v${finalAttrs.version}-${platform}";

  installPhase = ''
    runHook preInstall
    install -Dm755 dd-cli-v${finalAttrs.version}-${platform} $out/bin/dd-cli
    runHook postInstall
  '';

  passthru.updater = flake.lib.updater {
    kind = "platform-binaries";
    versionSource = {
      type = "github";
      owner = "doordash-oss";
      repo = "doordash-cli";
    };
    inherit urlTemplate platforms;
  };

  meta = with pkgs.lib; {
    description = "Terminal tool for ordering from DoorDash";
    longDescription = ''
      DoorDash CLI (dd-cli) is a terminal tool for ordering from DoorDash:
      search restaurants and stores, browse menus, build a cart, reorder a
      past order, and preview or check out, all from the command line.
    '';
    homepage = "https://github.com/doordash-oss/doordash-cli";
    downloadPage = "https://github.com/doordash-oss/doordash-cli/releases";
    changelog = "https://github.com/doordash-oss/doordash-cli/releases/tag/v${finalAttrs.version}";
    license = licenses.unfree;
    mainProgram = "dd-cli";
    platforms = lib.attrNames sources.hashes;
    sourceProvenance = [ sourceTypes.binaryNativeCode ];
  };
})
