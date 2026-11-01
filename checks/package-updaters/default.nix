{
  pkgs,
  flake,
  perSystem,
  ...
}:
# Every package that fetches an upstream release declares how it is updated:
# a `passthru.updater` for packages/update, or `passthru.updater = null` with
# a comment saying why it stays frozen. Updatable packages need
# meta.changelog, which their update commits link to.
let
  inherit (pkgs) lib;

  attempt =
    fallback: value:
    let
      r = builtins.tryEval value;
    in
    if r.success then r.value else fallback;

  # A fetcher: a fixed-output derivation that downloads from a URL. Vendored
  # dependency hashes (goModules, npmDeps) have no URL of their own.
  isFetch = v: attempt false (lib.isDerivation v && v ? outputHash && (v ? url || v ? urls));

  inspect =
    pkg:
    let
      passthru = attempt { } (pkg.passthru or { });
    in
    {
      fetches = attempt false (lib.any isFetch ([ (pkg.src or null) ] ++ lib.attrValues passthru));
      declared = passthru ? updater;
      # Forced without tryEval: a malformed updater config fails here.
      updatable = builtins.toJSON (passthru.updater or null) != "null";
      changelog = attempt null (pkg.meta.changelog or null);
    };

  # Blueprint only lists a package on the systems in its meta.platforms.
  perPackage = lib.zipAttrs (
    lib.attrValues (lib.mapAttrs (_: lib.mapAttrs (_: inspect)) flake.packages)
  );

  problems = lib.concatLists (
    lib.mapAttrsToList (
      name: seen:
      let
        any = f: lib.any f seen;
      in
      lib.optional (
        any (s: s.fetches) && !any (s: s.declared)
      ) "${name}: fetches an upstream source but sets no passthru.updater"
      ++ lib.optional (any (
        s: s.updatable && s.changelog == null
      )) "${name}: has an updater but no meta.changelog"
    ) perPackage
  );
in
pkgs.runCommand "package-updaters"
  {
    # The driver's own tests and lint run with the guard.
    tests = lib.attrValues perSystem.self.update.tests;
    report = lib.concatStringsSep "\n" problems;
    passAsFile = [ "report" ];
  }
  ''
    if [ -s "$reportPath" ]; then
      cat "$reportPath" >&2
      exit 1
    fi
    touch $out
  ''
