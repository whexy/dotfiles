{
  pkgs,
  perSystem,
}:

# `iphone-wda` builds, installs, launches and stops WebDriverAgent on the
# phones in ~/.config/iphone-wda/config.json, so each serves on its Tailscale
# address with no computer attached. `iphone-use-select` is the MCP server
# agents see: iPhone Use behind a phone chosen per session.
let
  inherit (pkgs) lib;
  python = pkgs.python313;

  # pymobiledevice3 tracks iOS releases closely; nixpkgs' copy lags and does
  # not evaluate on Darwin (pyimg4 is marked broken). It comes from PyPI,
  # pinned by hash in requirements.txt, regenerated from requirements.in with
  #   uv pip compile --universal --generate-hashes --python-version 3.13 \
  #     --no-header -o requirements.txt requirements.in
  # The venv lives outside the store, keyed by the lock and interpreter.
  venvKey = builtins.substring 0 16 (
    builtins.hashString "sha256" (
      builtins.unsafeDiscardStringContext "${python}" + builtins.readFile ./requirements.txt
    )
  );

  launcher = pkgs.writeShellApplication {
    name = "iphone-wda";
    runtimeInputs = [
      pkgs.uv
      pkgs.git
    ];
    text = ''
      data="''${XDG_DATA_HOME:-$HOME/.local/share}/iphone-wda"
      venv="$data/venv-${venvKey}"
      if [ ! -x "$venv/bin/python" ]; then
        mkdir -p "$data"
        rm -rf "$venv.partial"
        UV_PYTHON_DOWNLOADS=never uv venv --quiet --python ${lib.getExe python} "$venv.partial"
        uv pip install --quiet --python "$venv.partial/bin/python" \
          --require-hashes -r ${./requirements.txt}
        mv "$venv.partial" "$venv"
        find "$data" -maxdepth 1 -name 'venv-*' ! -name "venv-${venvKey}" -exec rm -rf {} +
      fi
      exec "$venv/bin/python" -I ${./iphone_wda.py} "$@"
    '';
  };

  selector = pkgs.writeShellApplication {
    name = "iphone-use-select";
    text = ''
      exec ${lib.getExe python} -I ${./iphone_use_select.py} \
        --server ${lib.getExe perSystem.self.iphone-use} \
        --launcher ${lib.getExe launcher} "$@"
    '';
  };
in
pkgs.symlinkJoin {
  name = "iphone-wda";
  paths = [
    launcher
    selector
  ];
  meta = {
    description = "Run WebDriverAgent on tailnet iPhones and let agents pick one per session";
    mainProgram = "iphone-wda";
    platforms = lib.platforms.unix;
  };
}
