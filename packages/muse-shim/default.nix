{ pkgs }:

# Loopback bridge that lets Muse Code run against CLIProxyAPI; see
# muse-shim.py for why the catalog path needs translating.
pkgs.stdenvNoCC.mkDerivation {
  pname = "muse-shim";
  version = "1.0.0";
  src = ./.;

  nativeBuildInputs = [ pkgs.python3 ];

  dontBuild = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 muse-shim.py $out/bin/muse-shim
    patchShebangs $out/bin/muse-shim
    runHook postInstall
  '';

  doCheck = true;
  checkPhase = ''
    runHook preCheck
    python3 -m unittest discover -s tests
    runHook postCheck
  '';

  meta = {
    description = "Loopback CLIProxyAPI bridge for Muse Code";
    mainProgram = "muse-shim";
    platforms = pkgs.lib.platforms.unix;
  };
}
