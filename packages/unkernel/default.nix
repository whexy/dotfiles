{ pkgs, flake, ... }:

# unkernel: a Linux kernel compiled to WebAssembly, with its CLI and the SDK
# a page embeds. The npm tarball is the whole runtime: the kernel bundle, a
# base system, and JavaScript with no dependencies. It boots the tab host's
# image (host/, `just tab`).
let
  inherit (pkgs) lib;
in
pkgs.stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "unkernel";
  version = "0.2.0-261127-3b71fa5";

  src = pkgs.fetchurl {
    url = "https://registry.npmjs.org/unkernel/-/unkernel-${finalAttrs.version}.tgz";
    hash = "sha512-GoHaEnhdJkK9JNU2q8uy1VYjhdnZrolQxPPpQIPr4wQQzK0PjICIOkvwSBo/PuEj8J0r4ygMHTKFEvJKsTRi8A==";
  };

  nativeBuildInputs = [ pkgs.makeWrapper ];

  dontBuild = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib/node_modules/unkernel
    cp -R dist package.json LICENSE LICENSE-MIT THIRD-PARTY.md $out/lib/node_modules/unkernel/

    makeWrapper ${lib.getExe pkgs.nodejs} $out/bin/unkernel \
      --add-flags $out/lib/node_modules/unkernel/dist/cli.mjs

    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    # The base shell needs no distro image, so this boots the bundled kernel.
    $out/bin/unkernel --distro none --no-net --timeout 60 --input '{2}poweroff\n' | grep -q 'reboot: Power down'
    runHook postInstallCheck
  '';

  passthru = {
    # The directory a page serves: web.mjs, its chunks and the kernel bundle.
    web = "${finalAttrs.finalPackage}/lib/node_modules/unkernel/dist";

    # Every release is a prerelease of the next version.
    updater = flake.lib.updater {
      kind = "nix-update";
      args = [ "--version=unstable" ];
    };
  };

  meta = {
    description = "Linux kernel compiled to WebAssembly, for Node and the browser";
    homepage = "https://unkernel.dev";
    changelog = "https://github.com/pithings/unkernel/releases/tag/v${finalAttrs.version}";
    license = with lib.licenses; [
      mit
      gpl2Only
    ];
    sourceProvenance = [ lib.sourceTypes.binaryBytecode ];
    mainProgram = "unkernel";
    platforms = lib.platforms.unix;
  };
})
