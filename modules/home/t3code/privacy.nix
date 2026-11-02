# T3's telemetry and tracing switches, bound to each T3 program with a
# wrapper so that they reach only T3's own processes.
{ lib, pkgs }:
rec {
  environment = {
    T3CODE_TELEMETRY_ENABLED = "false";
    # Also overrides the standard OTEL_SDK_DISABLED, so an OTLP endpoint set
    # elsewhere still exports nothing.
    T3CODE_OTEL_SDK_DISABLED = "true";
    # The local NDJSON trace file cannot be switched off, only emptied.
    T3CODE_TRACE_MIN_LEVEL = "None";
    T3CODE_TRACE_MAX_FILES = "1";
    T3CODE_TRACE_MAX_BYTES = "65536";
  };

  # The package with every program under bin/ wrapped, with `extra`
  # variables beside the switches; passthru and meta stay the package's own.
  wrapWith =
    extra: package:
    pkgs.symlinkJoin {
      name = "${package.name}-private";
      paths = [ package ];
      nativeBuildInputs = [ pkgs.makeWrapper ];
      postBuild = ''
        for program in $out/bin/*; do
          wrapProgram "$program" ${
            lib.concatStringsSep " " (
              lib.mapAttrsToList (name: value: "--set ${name} ${lib.escapeShellArg value}") (environment // extra)
            )
          }
        done
      '';
      inherit (package) passthru meta;
    };

  wrap = wrapWith { };
}
