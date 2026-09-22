# Native user configuration stays writable; only the catalog and policy inputs
# live in the store. Agent command names never invoke the selection UI.
{ pkgs, agentSettings }:
{
  name,
  package,
  entries,
  mcpServers ? { },
  maintainedSettings ? { },
  resetEnv ? [ ],
}:
let
  manifest = pkgs.writeText "${name}-settings-catalog.json" (
    builtins.toJSON {
      inherit
        name
        entries
        mcpServers
        maintainedSettings
        resetEnv
        ;
      real = "${package}/bin/${name}";
      fzf = "${pkgs.fzf}/bin/fzf";
    }
  );
  runtime = "${pkgs.lib.getExe agentSettings} ${manifest}";
  launcher = pkgs.writeShellScriptBin name ''
    exec ${runtime} launch "$@"
  '';
  selector = pkgs.writeShellScriptBin "${name}-select" ''
    exec ${runtime} select ${launcher}/bin/${name} "$@"
  '';
  sync = pkgs.writeShellScriptBin "${name}-settings-sync" ''
    exec ${runtime} sync "$@"
  '';
in
pkgs.runCommand "${name}-settings" { meta.mainProgram = name; } ''
  mkdir -p $out/bin
  for p in ${package}/*; do
    if [ "$(basename "$p")" != bin ]; then
      ln -s "$p" $out/
    fi
  done
  for p in ${package}/bin/*; do
    if [ "$(basename "$p")" != ${name} ]; then
      ln -s "$p" $out/bin/
    fi
  done
  ln -s ${launcher}/bin/${name} $out/bin/${name}
  ln -s ${selector}/bin/${name}-select $out/bin/${name}-select
  ln -s ${sync}/bin/${name}-settings-sync $out/bin/${name}-settings-sync
''
