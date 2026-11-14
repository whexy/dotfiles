{ pkgs, flake, ... }:

# Modern Web Guidance, Chrome's searchable corpus of web platform best
# practices, with the CLI its skill drives. The npm tarball bundles the CLI,
# its search index and the guides, so it runs offline, and its skills match
# the CLI they call.
let
  inherit (pkgs) lib;
in
pkgs.stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "modern-web-guidance";
  version = "1.0.0";

  src = pkgs.fetchurl {
    url = "https://registry.npmjs.org/modern-web-guidance/-/modern-web-guidance-${finalAttrs.version}.tgz";
    hash = "sha256-vXqmI60QcQqa1meP28wLiQyQPFT9ar/BJv9C3gHw5Xc=";
  };

  nativeBuildInputs = [ pkgs.makeWrapper ];

  dontBuild = true;

  installPhase = ''
    runHook preInstall

    # The CLI finds its index and guides beside itself.
    mkdir -p $out/lib
    cp -R skills/modern-web-guidance $out/lib/modern-web-guidance
    mkdir -p $out/share/skills
    cp -R skills/*/ $out/share/skills/

    # Every run would otherwise start a detached process that posts usage
    # to Google; this is its only network access.
    makeWrapper ${lib.getExe pkgs.nodejs} $out/bin/modern-web-guidance \
      --add-flags $out/lib/modern-web-guidance/modern-web.mjs \
      --set DISABLE_TELEMETRY 1

    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    $out/bin/modern-web-guidance search "light dismiss dialog" | grep -q '"id"'
    $out/bin/modern-web-guidance retrieve dark-mode | grep -q .
    runHook postInstallCheck
  '';

  passthru.updater = flake.lib.updater { kind = "nix-update"; };

  meta = {
    description = "Chrome's web platform best practices, searchable offline by agents";
    homepage = "https://developer.chrome.com/docs/modern-web-guidance";
    changelog = "https://github.com/GoogleChrome/modern-web-guidance/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.asl20;
    mainProgram = "modern-web-guidance";
    platforms = lib.platforms.unix;
  };
})
