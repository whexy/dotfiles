{
  pkgs,
  inputs,
  flake,
  system,
}:
let
  inherit (pkgs) lib python3;

  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./pyproject.toml
      ./updater
      ./tests
    ];
  };

  # Formats what an updater writes the way the pre-commit check expects.
  treefmt =
    (import ../../lib/dev-tools.nix { inherit inputs flake; } system).treefmtEval.config.build.wrapper;

  # The CI image lacks most tools. `nix` stays on the caller's PATH so
  # evaluation uses the caller's store and settings.
  tools = [
    pkgs.git
    pkgs.jq
    pkgs.nix-update
    pkgs.nodejs
    treefmt
  ];

  sourceCheck =
    name: nativeBuildInputs: script:
    pkgs.runCommand "update-${name}" { inherit nativeBuildInputs; } ''
      cp -r ${src} source && chmod -R u+w source && cd source
      export HOME=$TMPDIR
      ${script}
      touch $out
    '';
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
    unit = sourceCheck "unit" [ python3 ] ''
      python3 -m unittest discover -s tests -t . -v
    '';
    lint = sourceCheck "lint" [ pkgs.ruff ] ''
      ruff check --no-cache .
      ruff format --no-cache --check .
    '';
  };

  meta = {
    description = "Update the upstream pins of this flake's packages";
    mainProgram = "update";
    platforms = lib.platforms.unix;
  };
}
