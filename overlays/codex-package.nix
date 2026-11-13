{
  lib,
  stdenv,
  runCommand,
  codex,
  ripgrep,
  bubblewrap,
  patchelf,
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
    nativeBuildInputs = lib.optional stdenv.hostPlatform.isLinux patchelf;
    passthru.unwrapped = codex;
  }
  ''
    mkdir -p "$out/bin" "$out/codex-path" "$out/codex-resources"
    ${
      if stdenv.hostPlatform.isLinux then
        # Codex links aws-lc as unversioned libssl.so/libcrypto.so. Hosts that
        # put nix-ld's directory on LD_LIBRARY_PATH (incus-container with
        # NVIDIA) would shadow them with OpenSSL, which lacks aws-lc symbols
        # such as EC_group_p384. DT_RPATH is searched before LD_LIBRARY_PATH;
        # DT_RUNPATH is not.
        ''
          cp -L ${codex}/libexec/codex/bin/* "$out/bin/"
          chmod u+w "$out"/bin/*
          for f in "$out"/bin/*; do
            patchelf --force-rpath --set-rpath "$(patchelf --print-rpath "$f")" "$f"
          done
          chmod u-w "$out"/bin/*
        ''
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
