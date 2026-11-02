{
  pkgs,
  flake,
}:

# The T3 Code desktop app on Linux, at the upstream nightly whexy/t3code's
# server (t3code-fork) builds; update.py follows that version, so the pin
# moves only with the fork's. macOS installs T3's signed app instead, which
# updates itself (modules/home/t3code).
let
  inherit (pkgs) lib;
  sources = lib.importJSON ./sources.json;
  inherit (sources) version;
  inherit (pkgs.stdenv.hostPlatform) system;

  pname = "t3code-desktop";
  platform =
    {
      aarch64-linux = {
        name = "linux-arm64";
        arch = "arm64";
      };
      x86_64-linux = {
        name = "linux-x64";
        arch = "x86_64";
      };
    }
    .${system} or (throw "t3code-desktop-nightly: unsupported system ${system}");

  src = pkgs.fetchurl {
    url = "https://github.com/pingdotgg/t3code/releases/download/v${version}/T3-Code-${version}-${platform.arch}.AppImage";
    hash = sources.hashes.${platform.name};
  };

  contents = pkgs.appimageTools.extract { inherit pname version src; };
in
pkgs.appimageTools.wrapAppImage {
  inherit pname version;
  src = contents;

  # Nix pins the app, so its own updater stays off. At every launch the app
  # writes a URL-handler entry that runs T3CODE_DESKTOP_LAUNCHER_PATH;
  # without it, the entry would run the Electron binary outside this FHS
  # environment.
  extraInstallCommands = ''
    install -Dm444 ${contents}/t3code.desktop -t $out/share/applications
    substituteInPlace $out/share/applications/t3code.desktop \
      --replace-fail 'Exec=AppRun' 'Exec=${pname}'
    cp -r ${contents}/usr/share/icons $out/share/

    . ${pkgs.makeWrapper}/nix-support/setup-hook
    wrapProgram $out/bin/${pname} \
      --set T3CODE_DISABLE_AUTO_UPDATE true \
      --set T3CODE_DESKTOP_LAUNCHER_PATH $out/bin/${pname}
  '';

  passthru.updater = flake.lib.updater { kind = "script"; };

  meta = {
    description = "Nightly T3 Code desktop app";
    homepage = "https://t3.codes";
    changelog = "https://github.com/pingdotgg/t3code/releases/tag/v${version}";
    license = lib.licenses.mit;
    mainProgram = pname;
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
  };
}
