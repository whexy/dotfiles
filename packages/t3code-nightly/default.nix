{
  pkgs,
  flake,
  inputs,
}:

let
  inherit (pkgs) lib;
  sources = lib.importJSON ./sources.json;
  platform =
    {
      aarch64-darwin = "darwin-arm64";
      aarch64-linux = "linux-arm64";
      x86_64-linux = "linux-x64";
    }
    .${pkgs.stdenv.hostPlatform.system}
      or (throw "t3code-nightly: unsupported system ${pkgs.stdenv.hostPlatform.system}");

  # T3's preview tools download this Chrome for Testing build into
  # `~/.t3/tools/chrome-headless-shell/<platform>/<version>` on first use, and
  # it cannot find its libraries on NixOS. T3 skips the download when an
  # executable already sits there, so Home Manager links this patched copy in.
  # Darwin keeps T3's own download, which runs as is.
  browser = pkgs.stdenvNoCC.mkDerivation (browserAttrs: {
    pname = "t3code-chrome-headless-shell";
    inherit (sources.browser) version;

    passthru.platform =
      {
        aarch64-linux = "linux-arm64";
        x86_64-linux = "linux64";
      }
      .${pkgs.stdenv.hostPlatform.system};

    src = pkgs.fetchurl {
      url = "https://storage.googleapis.com/chrome-for-testing-public/${browserAttrs.version}/${browserAttrs.passthru.platform}/chrome-headless-shell-${browserAttrs.passthru.platform}.zip";
      hash = sources.browser.hashes.${browserAttrs.passthru.platform};
    };

    sourceRoot = "chrome-headless-shell-${browserAttrs.passthru.platform}";

    nativeBuildInputs = [
      pkgs.autoPatchelfHook
      pkgs.unzip
    ];

    buildInputs = with pkgs; [
      alsa-lib
      at-spi2-core
      atk
      dbus
      expat
      glib
      libgbm
      libx11
      libxcb
      libxcomposite
      libxdamage
      libxext
      libxfixes
      libxkbcommon
      libxrandr
      nspr
      nss
      stdenv.cc.cc.lib
      udev
    ];

    dontStrip = true;

    installPhase = ''
      runHook preInstall
      cp -R . "$out"
      runHook postInstall
    '';

    meta = {
      description = "Chrome for Testing headless shell pinned by T3 Code";
      homepage = "https://googlechromelabs.github.io/chrome-for-testing/";
      license = lib.licenses.bsd3;
      platforms = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    };
  });

  upstream = pkgs.stdenvNoCC.mkDerivation (finalAttrs: {
    pname = "t3code-nightly";
    inherit (sources) version;

    # The `t3` npm package no longer carries per-platform builds; it downloads
    # this archive from the GitHub Release, so fetch it there directly.
    src = pkgs.fetchurl {
      url = "https://github.com/pingdotgg/t3code/releases/download/v${finalAttrs.version}/t3-${finalAttrs.version}-${platform}.tar.gz";
      hash = sources.hashes.${platform};
    };

    sourceRoot = "t3-${finalAttrs.version}-${platform}";

    nativeBuildInputs = lib.optionals pkgs.stdenv.hostPlatform.isLinux [
      pkgs.autoPatchelfHook
    ];

    buildInputs = lib.optionals pkgs.stdenv.hostPlatform.isLinux [
      pkgs.glibc
      pkgs.stdenv.cc.cc.lib
    ];

    # Native addons ship musl prebuilds beside the glibc ones and load them only
    # on a musl libc, so their libc never has to resolve here.
    autoPatchelfIgnoreMissingDeps = [ "libc.musl-*.so.1" ];

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

    passthru = {
      # Upstream's prebuilt server ignores T3CODE_DEV_MANAGED_POLICY_PATH.
      honorsManagedPolicyPath = false;

      # update.py also pins the desktop app and the browser, which
      # t3code-desktop-nightly and the hub image read from sources.json.
      updater = flake.lib.updater {
        kind = "script";
        alsoBuild = [
          "t3code-nightly.browser"
          "t3code-desktop-nightly"
          "t3code-hub-image"
        ];
      };
    }
    // lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux { inherit browser; };

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
  });

  # x86_64-linux runs whexy/t3code's server, which reads
  # T3CODE_DEV_MANAGED_POLICY_PATH; the other platforms keep upstream's. The
  # nightly the fork builds is sources.json's version, which also pins the
  # browser, the desktop app and the hub image's tag.
  fork =
    if pkgs.stdenv.hostPlatform.system == "x86_64-linux" then
      inputs.t3code-fork.packages.x86_64-linux.t3-server
    else
      null;
in
if fork == null then
  upstream
else
  # The fork's own derivation, so the store path is the one CI cached; these
  # attributes leave what it builds unchanged.
  let
    passthru = {
      inherit (upstream) browser updater;
      honorsManagedPolicyPath = true;
    };
  in
  fork
  // passthru
  // {
    passthru = fork.passthru or { } // passthru;
    meta = fork.meta // {
      changelog = "https://github.com/whexy/t3code/commits/${inputs.t3code-fork.rev}";
    };
  }
