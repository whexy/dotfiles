{
  lib,
  stdenv,
  runCommand,
  codex,
  ripgrep,
  bubblewrap,
}:
let
  manifest = builtins.toJSON {
    layoutVersion = 1;
    inherit (codex) version;
    target = stdenv.hostPlatform.rust.rustcTarget;
    variant = "cli";
    entrypoint = "bin/codex";
    resourcesDir = "codex-resources";
    pathDir = "codex-path";
  };
in
# The daemon copies and validates a complete package, rejecting links outside
# its root. Repackage the cached binaries without rebuilding Codex's Rust crates.
runCommand "codex-${codex.version}-packaged"
  {
    inherit (codex) version meta;
    passthru.unwrapped = codex;
  }
  ''
    mkdir -p "$out/bin" "$out/codex-path" "$out/codex-resources"
    ${
      if stdenv.hostPlatform.isLinux then
        ''cp -L ${codex}/libexec/codex/bin/* "$out/bin/"''
      else
        ''cp -L ${codex}/bin/* "$out/bin/"''
    }
    cp -L ${lib.getExe ripgrep} "$out/codex-path/rg"
    ${lib.optionalString stdenv.hostPlatform.isLinux ''
      cp -L ${lib.getExe bubblewrap} "$out/codex-resources/bwrap"
    ''}
    printf '%s\n' ${lib.escapeShellArg manifest} > "$out/codex-package.json"
    if [ -d ${codex}/share ]; then
      cp -rL ${codex}/share "$out/share"
    fi
  ''
