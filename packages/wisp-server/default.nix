{ pkgs, flake, ... }:

# wisp-server-python: a Wisp proxy, which carries TCP and UDP streams for a
# client over one WebSocket. The tab host's page reaches the internet through
# it (packages/unkernel/host).
let
  inherit (pkgs) lib;
  python = pkgs.python3.pkgs;

  # nixpkgs has no asyncudp. Its last release is from 2023, so it is pinned
  # here with no updater of its own.
  asyncudp = python.buildPythonPackage (finalAttrs: {
    pname = "asyncudp";
    version = "0.11.0";
    pyproject = true;

    src = pkgs.fetchPypi {
      inherit (finalAttrs) pname version;
      hash = "sha256-yKtkWfTcjrxC9AHTvXLCpsaAjRDkIjHzngxDOsZGq/k=";
    };

    build-system = [ python.setuptools ];

    pythonImportsCheck = [ "asyncudp" ];
  });
in
python.buildPythonApplication (finalAttrs: {
  pname = "wisp-server";
  version = "0.11.0";
  pyproject = true;

  src = pkgs.fetchPypi {
    pname = "wisp_python";
    inherit (finalAttrs) version;
    hash = "sha256-NS5EmwSK5fk6eZ8RIi0KBHGJjnQMxFKzzRkLs0KUP4I=";
  };

  build-system = [
    python.setuptools
    python.toml
  ];

  dependencies = [
    asyncudp
    python.psutil
    python.python-socks
    python.uvloop
    python.websockets
  ];

  # The project declares no entry point; upstream runs `python -m wisp.server`.
  postInstall = ''
    install -Dm755 src/wisp/server/__main__.py $out/bin/wisp-server
    sed -i '1i #!${python.python.interpreter}' $out/bin/wisp-server
  '';

  pythonImportsCheck = [ "wisp.server" ];

  passthru.updater = flake.lib.updater { kind = "nix-update"; };

  meta = {
    description = "Wisp proxy server, which carries TCP and UDP for a WebSocket client";
    homepage = "https://github.com/MercuryWorkshop/wisp-server-python";
    changelog = "https://github.com/MercuryWorkshop/wisp-server-python/commits/main";
    license = lib.licenses.agpl3Plus;
    mainProgram = "wisp-server";
    platforms = lib.platforms.unix;
  };
})
