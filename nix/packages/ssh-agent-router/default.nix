{ pkgs }:
pkgs.stdenvNoCC.mkDerivation {
  pname = "ssh-agent-router";
  version = "1.0.0";
  src = ./.;

  nativeBuildInputs = [ pkgs.makeWrapper ];
  nativeCheckInputs = [
    pkgs.python3
    pkgs.openssh
  ];
  doCheck = true;
  checkPhase = ''
    runHook preCheck
    python3 -m unittest -v
    runHook postCheck
  '';
  installPhase = ''
    runHook preInstall
    install -Dm644 router.py $out/lib/ssh-agent-router/router.py
    makeWrapper ${pkgs.python3}/bin/python3 $out/bin/ssh-agent-router \
      --add-flags "$out/lib/ssh-agent-router/router.py"
    runHook postInstall
  '';

  meta = {
    description = "Newest-live forwarded SSH agent routing for terminal multiplexers";
    mainProgram = "ssh-agent-router";
    platforms = pkgs.lib.platforms.unix;
  };
}
