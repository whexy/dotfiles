{ pkgs, flake }:

let
  inherit (pkgs) lib;
  sources = lib.importJSON ./sources.json;
  # The download's file name; the release manifest spells it with `_`.
  platforms = {
    aarch64-darwin = "aarch64-macos";
    aarch64-linux = "aarch64-linux";
    x86_64-darwin = "x86-macos";
    x86_64-linux = "x86-linux";
  };
  platform =
    platforms.${pkgs.stdenv.hostPlatform.system}
      or (throw "muse-code: unsupported system ${pkgs.stdenv.hostPlatform.system}");
in
# Meta publishes only a launcher that downloads the real binary outside the
# store and self-updates it, so package the binary the launcher would fetch.
# It is statically linked on Linux and signed on macOS, so it runs as-is.
pkgs.stdenvNoCC.mkDerivation {
  pname = "muse-code";
  inherit (sources) version;

  src = pkgs.fetchurl {
    url = "https://lookaside.facebook.com/lookaside/muse/download/?channel=muse&version=${sources.version}&file=muse-${platform}";
    hash = sources.hashes.${pkgs.stdenv.hostPlatform.system};
  };

  dontUnpack = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 $src $out/bin/muse
    runHook postInstall
  '';

  nativeInstallCheckInputs = [ pkgs.versionCheckHook ];
  doInstallCheck = true;

  passthru.updater = flake.lib.updater {
    kind = "manifest-checksums";
    versionSource = {
      type = "json";
      url = "https://api.meta.ai/muse-code/channels/muse-stable";
      path = "version";
    };
    manifestUrl = "https://lookaside.facebook.com/lookaside/muse/download/?channel=muse&version={version}&file=manifest.json";
    checksumPath = "artifacts.{platform}.checksum";
    platforms = lib.mapAttrs (_: p: lib.replaceStrings [ "-" ] [ "_" ] p) platforms;
  };

  meta = {
    description = "Meta's Muse Code terminal coding agent";
    homepage = "https://dev.meta.ai/docs/muse-code";
    mainProgram = "muse";
    changelog = "https://dev.meta.ai/docs/muse-code/changelog";
    platforms = lib.attrNames sources.hashes;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
