# Self-expiring overlay: firefox-devtools-mcp needs --auto-profile (0.9.10)
# and --tool-preset (0.9.15), but nixpkgs-unstable still ships 0.9.9, where
# both flags are silently ignored rather than rejected.
#
# Once nixpkgs-unstable ships >= 0.9.15 this overlay becomes a no-op and emits
# a warning reminding to remove it.
#
# Requires the `unstable` overlay (pkgs.unstable) to be applied before this one.
_final: prev:
let
  neededVersion = "0.9.15";
  pinnedVersion = "0.10.2";
  upstream = prev.unstable.firefox-devtools-mcp;
  noOverride = prev.lib.versionAtLeast upstream.version neededVersion;

  pinnedSrc = prev.fetchFromGitHub {
    owner = "mozilla";
    repo = "firefox-devtools-mcp";
    tag = "v${pinnedVersion}";
    hash = "sha256-WSlFNT0aG2DrP5hK1eDT47yb2L9NLztc81FBn1+jiT4=";
  };
in
{
  unstable = prev.unstable // {
    firefox-devtools-mcp =
      prev.lib.warnIf noOverride
        ''
          firefox-devtools-mcp >= ${neededVersion} is now in nixpkgs-unstable; the
          firefox-devtools-mcp-profile overlay can be removed.
        ''
        (
          if noOverride then
            upstream
          else
            upstream.overrideAttrs {
              version = pinnedVersion;
              src = pinnedSrc;

              npmDeps = prev.fetchNpmDeps {
                src = pinnedSrc;
                name = "firefox-devtools-mcp-${pinnedVersion}-npm-deps";
                hash = "sha256-s9SSFvbcNxxOVCIWbo1079Ysxqy2Z6+XyZoeMZXRB68=";
              };

              # 0.9.9 hardcoded a stale server version that nixpkgs patched out;
              # upstream injects it at build time since 0.10.0, so the substitution
              # no longer has anything to match.
              postPatch = "";
            }
        );
  };
}
