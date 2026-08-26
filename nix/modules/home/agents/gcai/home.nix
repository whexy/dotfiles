{
  pkgs,
  lib,
  perSystem,
  model,
}:
{
  # Stamp the configured model into gcai via GCAI_MODEL.
  packages = [
    (pkgs.writeShellScriptBin "gcai" ''
      export GCAI_MODEL=${lib.escapeShellArg model}
      exec ${perSystem.self.gcai}/bin/gcai "$@"
    '')
  ];
}
