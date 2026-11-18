{ pkgs, flake, ... }:

# wdl, the CLI that bundles and releases Workers to a self-hosted WDL
# platform (https://github.com/wdl-dev/wdl). It bundles with the Wrangler it
# depends on, which it finds beside itself, and runs only Wrangler's
# `deploy --dry-run`, so workerd is never started and needs no patching.
let
  inherit (pkgs) lib;

  # devDependencies only serve upstream's own lint, typecheck and tests.
  lockfileFilter = "del(.devDependencies)";
  npm = flake.lib.npmTarball {
    inherit pkgs lockfileFilter;
    lockfile = ./package-lock.json;
  };
in
pkgs.buildNpmPackage (finalAttrs: {
  pname = "wdl";
  version = "1.9.4";

  src = pkgs.fetchurl {
    url = "https://registry.npmjs.org/@wdl-dev/cli/-/cli-${finalAttrs.version}.tgz";
    hash = "sha256-ODVutCPLcWTBktZ22Hjb6N0t1mAmk2CPJzzE1S1vYxQ=";
  };

  npmDepsHash = "sha256-5rfVvNMNwJcPD8glFW8Lohp62ndkYXezblGzrn9sTxM=";

  inherit (npm) postPatch dontNpmBuild;

  nativeInstallCheckInputs = [ pkgs.versionCheckHook ];
  doInstallCheck = true;

  passthru.updater = flake.lib.updater {
    kind = "npm";
    package = "@wdl-dev/cli";
    inherit lockfileFilter;
  };

  meta = {
    description = "CLI for building and releasing Workers on a self-hosted WDL platform";
    homepage = "https://github.com/wdl-dev/cli";
    changelog = "https://github.com/wdl-dev/cli/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.asl20;
    mainProgram = "wdl";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
      "aarch64-darwin"
    ];
  };
})
