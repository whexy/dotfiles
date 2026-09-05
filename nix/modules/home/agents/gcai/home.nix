{
  pkgs,
  lib,
  perSystem,
  defaults,
}:
{
  # Stamp the configured model into gcai via GCAI_MODEL.
  packages = [
    (pkgs.writeShellScriptBin "gcai" ''
      export GCAI_MODEL=${lib.escapeShellArg defaults.cheap}
      exec ${perSystem.self.gcai}/bin/gcai "$@"
    '')
  ];
}
