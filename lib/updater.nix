# Validate a package's `passthru.updater`, the data packages/update runs, so a
# misspelled or missing field fails evaluation instead of the nightly update.
{ lib }:
let
  kinds = {
    nix-update = {
      required = [ ];
      optional = [ "args" ];
    };
    github-branch = {
      required = [
        "owner"
        "repo"
      ];
      optional = [ ];
    };
    npm = {
      required = [ "lockfileFilter" ];
      optional = [
        "package"
        "distTag"
        # Dependencies whose install script downloads a prebuilt archive:
        # each name maps to its `urlTemplate` and `platforms`.
        "prebuilds"
      ];
    };
    platform-binaries = {
      required = [
        "versionSource"
        "urlTemplate"
        "platforms"
      ];
      optional = [ ];
    };
    manifest-checksums = {
      required = [
        "versionSource"
        "manifestUrl"
        "checksumPath"
        "platforms"
      ];
      optional = [ ];
    };
    script = {
      required = [ ];
      # Data the package's update.py reads, so it shares one value with the
      # package's own expression.
      optional = [ "settings" ];
    };
  };

  # Every kind takes these.
  common = [
    "kind"
    # Packages that read this package's pins, built along with it.
    "alsoBuild"
    # The upstream moves its pointer back, and the pin follows it.
    "allowDowngrade"
    # Passthru fetchers whose hash follows the package version.
    "subpackages"
    # Passthru fetchers that move to their default branch's head whenever
    # the package moves.
    "followBranch"
  ];

  versionSources = {
    github = [
      "owner"
      "repo"
    ];
    npm = [ "package" ];
    pypi = [ "package" ];
    json = [
      "url"
      "path"
    ];
  };

  prebuildFields = [
    "urlTemplate"
    "platforms"
  ];

  fail = msg: throw "passthru.updater: ${msg}";

  checkFields =
    what: required: allowed: attrs:
    let
      missing = lib.filter (f: !(attrs ? ${f})) required;
      unknown = lib.filter (f: !(lib.elem f allowed)) (lib.attrNames attrs);
    in
    if missing != [ ] then
      fail "${what} is missing ${lib.concatStringsSep ", " missing}"
    else if unknown != [ ] then
      fail "${what} has unknown ${lib.concatStringsSep ", " unknown}"
    else
      attrs;

  checkVersionSource =
    source:
    let
      type = source.type or (fail "versionSource is missing type");
      required =
        versionSources.${type}
          or (fail "unknown versionSource type '${type}' (known: ${lib.concatStringsSep ", " (lib.attrNames versionSources)})");
    in
    checkFields "versionSource '${type}'" required ([ "type" ] ++ required) source;
in
config:
let
  kind = config.kind or (fail "missing kind");
  spec =
    kinds.${kind}
      or (fail "unknown kind '${kind}' (known: ${lib.concatStringsSep ", " (lib.attrNames kinds)})");
  checked = checkFields "kind '${kind}'" spec.required (
    common ++ spec.required ++ spec.optional
  ) config;
in
builtins.seq checked (
  config
  // lib.optionalAttrs (config ? versionSource) {
    versionSource = checkVersionSource config.versionSource;
  }
  // lib.optionalAttrs (config ? prebuilds) {
    prebuilds = lib.mapAttrs (
      name: checkFields "prebuild '${name}'" prebuildFields prebuildFields
    ) config.prebuilds;
  }
)
