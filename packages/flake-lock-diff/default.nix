{ pkgs }:
pkgs.stdenvNoCC.mkDerivation {
  pname = "flake-lock-diff";
  version = "1.0.0";
  src = ./.;

  nativeBuildInputs = [ pkgs.makeWrapper ];
  nativeCheckInputs = [ pkgs.python3 ];
  doCheck = true;
  checkPhase = ''
    runHook preCheck
    python3 -m unittest -v
    runHook postCheck
  '';
  # `nix` stays on the caller's PATH so evaluation uses the caller's store
  # and settings, such as the CI container's single-user store.
  installPhase = ''
    runHook preInstall
    install -Dm644 flake_lock_diff.py $out/lib/flake-lock-diff/flake_lock_diff.py
    makeWrapper ${pkgs.python3}/bin/python3 $out/bin/flake-lock-diff \
      --add-flags "$out/lib/flake-lock-diff/flake_lock_diff.py"
    runHook postInstall
  '';

  meta = {
    description = "Report package version changes between two flake.lock files";
    mainProgram = "flake-lock-diff";
    platforms = pkgs.lib.platforms.unix;
  };
}
