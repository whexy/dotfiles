{
  pkgs,
  perSystem,
  flake,
}:
let
  inherit (pkgs) lib python3;

  fileset = lib.fileset.unions [
    ./pyproject.toml
    ./updater
    ./tests
  ];
  src = lib.fileset.toSource {
    root = ./.;
    inherit fileset;
  };

  # Formats what an updater writes the way the pre-commit check expects.
  treefmt = perSystem.self.formatter;

  # The CI image lacks most tools. `nix` stays on the caller's PATH so
  # evaluation uses the caller's store and settings.
  tools = [
    pkgs.git
    pkgs.jq
    pkgs.nix-update
    pkgs.nodejs
    treefmt
  ];

  checks = flake.lib.pythonChecks {
    inherit pkgs fileset;
    dir = ./.;
    # The `script` kind's update.py files import the updater, so its tests
    # cover them too.
    extraFiles = lib.fileset.toList (lib.fileset.fileFilter (file: file.name == "update.py") ../.);
  };
in
pkgs.stdenvNoCC.mkDerivation {
  pname = "update";
  version = "1.0.0";
  inherit src;

  nativeBuildInputs = [ pkgs.makeWrapper ];

  # `-P` keeps the working directory, the repository, off the module path.
  installPhase = ''
    runHook preInstall
    mkdir -p $out/lib/update
    cp -r updater $out/lib/update/
    makeWrapper ${python3}/bin/python3 $out/bin/update \
      --add-flags "-P -m updater" \
      --prefix PYTHONPATH : $out/lib/update \
      --prefix PATH : ${lib.makeBinPath tools} \
      --set-default SSL_CERT_FILE ${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt
    runHook postInstall
  '';

  passthru.tests = {
    unit = checks.sourceTest "unit" [ python3 ] ''
      python3 -m unittest discover -s tests -t . -v
    '';
    inherit (checks) lint typecheck;
  };

  meta = {
    description = "Update the upstream pins of this flake's packages";
    mainProgram = "update";
    platforms = lib.platforms.unix;
  };
}
