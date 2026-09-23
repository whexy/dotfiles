{ pkgs }:
let
  inherit (pkgs) lib;
  shared = import ../../modules/home/panel/ai-quota/shared.nix;
  python = pkgs.python3.withPackages (ps: [ ps.pyside6 ]);
  metadata = pkgs.writeText "ai-quota-popup-config.json" (
    builtins.toJSON {
      inherit (shared) apiUrl updateInterval;
      providers = map (p: {
        inherit (p) name title;
      }) shared.providers;
    }
  );
in
pkgs.stdenvNoCC.mkDerivation {
  pname = "ai-quota-popup";
  version = "0.1.0";
  src = ./.;

  nativeBuildInputs = [
    pkgs.makeWrapper
    pkgs.qt6.wrapQtAppsHook
  ];
  buildInputs = [
    pkgs.qt6.qtdeclarative
  ]
  ++ lib.optionals pkgs.stdenv.isLinux [ pkgs.qt6.qtwayland ];
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    install -d "$out/bin" "$out/share/ai-quota-popup/logos"
    install -m 0644 main.py view.qml "$out/share/ai-quota-popup/"
    install -m 0644 ${metadata} "$out/share/ai-quota-popup/config.json"
    install -m 0644 ${../../modules/home/panel/ai-quota/summary.jq} "$out/share/ai-quota-popup/summary.jq"
    ${lib.concatMapStringsSep "\n" (p: ''
      install -m 0644 ${p.logo} "$out/share/ai-quota-popup/logos/${p.name}.png"
    '') shared.providers}
    makeWrapper ${python}/bin/python3 "$out/bin/ai-quota-popup" \
      --add-flags "$out/share/ai-quota-popup/main.py" \
      --prefix PATH : ${
        lib.makeBinPath [
          pkgs.curl
          pkgs.jq
        ]
      }
    runHook postInstall
  '';

  meta = {
    description = "Unified quota detail popup for desktop bars";
    mainProgram = "ai-quota-popup";
    platforms = lib.platforms.linux ++ lib.platforms.darwin;
  };
}
