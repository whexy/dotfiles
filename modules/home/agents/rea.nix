# REA's optional engines.
#
# REA never installs or searches for these; each is selected by an absolute
# path in a `REA_*` variable. Enabled groups are baked into a wrapper around
# the package, so the MCP server and the CLI on PATH see the same set.
{
  pkgs,
  lib,
  cfg,
  perSystem,
}:
let
  base = perSystem.self.rea-agents;

  # REA checks the exact profile it was verified against and refuses others.
  pwntoolsPython =
    let
      unicorn = pkgs.unicorn.overrideAttrs (
        finalAttrs: _: {
          version = "2.1.2";
          src = pkgs.fetchFromGitHub {
            owner = "unicorn-engine";
            repo = "unicorn";
            tag = finalAttrs.version;
            hash = "sha256-qA84xBztyWmt/rUExhhZMkQzvDPx0UE9MAIPG/Su3iE=";
          };
        }
      );
      python = pkgs.python3.override {
        self = python;
        packageOverrides = pyself: super: {
          pyelftools = super.pyelftools.overridePythonAttrs (old: {
            version = "0.33";
            src = old.src.override {
              tag = "v0.33";
              hash = "sha256-NqF5A6PRl4uncwNS9j44fIV7ovlljiucvV2Msv0LK/w=";
            };
          });
          # This release reads its version from git, absent from the tarball.
          unicorn = (super.unicorn.override { inherit unicorn; }).overridePythonAttrs (old: {
            build-system = old.build-system ++ [ pyself.versioningit ];
            postPatch = ''
              substituteInPlace pyproject.toml --replace-fail '[tool.versioningit]' \
                '[tool.versioningit]
              default-version = "${unicorn.version}"'
            '';
          });
        };
      };
    in
    python.withPackages (ps: [ ps.pwntools ]);

  # pwndbg's own environment: GDB, gdbinit.py and the venv REA points it at.
  pwndbgVenv = perSystem.pwndbg.pwndbg.meta.pwndbgVenv;
  # pwndbg turns debuginfod back on after REA disables it, and this GDB has a
  # built-in server list, so it downloads libraries by build-id and loads one
  # as the executable. REA then rejects the session as no longer core-only.
  # A blank URL list is the one setting that resolves nothing.
  pwndbgGdb = pkgs.writeShellScript "rea-pwndbg-gdb" ''
    export DEBUGINFOD_URLS=" "
    exec ${pwndbgVenv}/bin/gdb "$@"
  '';

  jadxMcpJar = pkgs.fetchurl {
    url = "https://github.com/1013503897/jadx-headless-mcp/releases/download/v0.7.1/jadx-headless-mcp-0.7.1-all.jar";
    hash = "sha256-bl6s9QC2QpK/tzxJeXwZWPbuRGRuQ+hoA5rn/rVz/3U=";
  };

  unstable = perSystem.nixpkgs-unstable;

  browser = lib.getExe pkgs.chromium;

  environment =
    lib.optionalAttrs cfg.browser.enable {
      REA_BROWSER_EXECUTABLE = browser;
    }
    // lib.optionalAttrs cfg.android.enable {
      REA_ADB_PATH = lib.getExe' pkgs.android-tools "adb";
      REA_APKTOOL_COMMAND = lib.getExe pkgs.apktool;
      REA_JADX_MCP_JAR = jadxMcpJar;
    }
    // lib.optionalAttrs cfg.binary.enable {
      REA_PWNTOOLS_PYTHON = lib.getExe pwntoolsPython;
      REA_PWNDBG_GDB = "${pwndbgGdb}";
      REA_PWNDBG_GDBINIT = "${pwndbgVenv}/share/pwndbg/gdbinit.py";
      REA_PWNDBG_VENV_PATH = "${pwndbgVenv}";
    }
    // lib.optionalAttrs cfg.firmware.enable {
      REA_BINWALK_COMMAND = lib.getExe pkgs.binwalk;
      # REA's adapter targets 26.6.x, which only unstable has.
      REA_UNBLOB_COMMAND = lib.getExe unstable.unblob;
    }
    // lib.optionalAttrs cfg.javascript.enable {
      REA_WAKARU_COMMAND = lib.getExe perSystem.self.wakaru;
    }
    // lib.optionalAttrs cfg.networkCapture.enable {
      REA_MITMDUMP_COMMAND = lib.getExe' pkgs.mitmproxy "mitmdump";
    }
    // lib.optionalAttrs cfg.dotnet.enable {
      REA_ILSPY_CMD_PATH = lib.getExe pkgs.ilspycmd;
    }
    // cfg.environment;
in
{
  inherit base;

  package =
    if environment == { } then
      base
    else
      pkgs.symlinkJoin {
        inherit (base) name meta;
        paths = [ base ];
        nativeBuildInputs = [ pkgs.makeWrapper ];
        postBuild = ''
          for program in rea rea-agents; do
            wrapProgram $out/bin/$program \
              ${lib.concatStringsSep " " (
                lib.mapAttrsToList (name: value: "--set-default ${name} ${lib.escapeShellArg value}") environment
              )}
          done
        '';
      };

  # Browser scenarios take the executable as a tool argument, so the agent
  # has to be able to read the path from its own environment.
  sessionVariables = lib.optionalAttrs cfg.browser.enable {
    REA_BROWSER_EXECUTABLE = browser;
  };
}
