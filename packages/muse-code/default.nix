{ pkgs }:

let
  inherit (pkgs) lib;
  metadata = import ./metadata.nix;
  platform =
    {
      aarch64-darwin = "aarch64-macos";
      aarch64-linux = "aarch64-linux";
      x86_64-darwin = "x86-macos";
      x86_64-linux = "x86-linux";
    }
    .${pkgs.stdenv.hostPlatform.system}
      or (throw "muse-code: unsupported system ${pkgs.stdenv.hostPlatform.system}");
in
# Meta publishes only a launcher that downloads the real binary outside the
# store and self-updates it, so package the binary the launcher would fetch.
# It is statically linked on Linux and signed on macOS, so it runs as-is.
pkgs.stdenvNoCC.mkDerivation {
  pname = "muse-code";
  inherit (metadata) version;

  src = pkgs.fetchurl {
    url = "https://lookaside.facebook.com/lookaside/muse/download/?channel=muse&version=${metadata.version}&file=muse-${platform}";
    hash = metadata.hashes.${pkgs.stdenv.hostPlatform.system};
  };

  dontUnpack = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 $src $out/bin/muse
    runHook postInstall
  '';

  meta = {
    description = "Meta's Muse Code terminal coding agent";
    homepage = "https://dev.meta.ai/docs/muse-code";
    mainProgram = "muse";
    platforms = lib.attrNames metadata.hashes;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
