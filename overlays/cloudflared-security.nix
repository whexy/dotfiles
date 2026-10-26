# Self-expiring overlay: cloudflared < 2026.10.2 trusts certificates from the
# compromised eMudhra keys, and macOS builds not installed with Homebrew need
# 2026.10.3. The stable channels still ship 2026.5.2 and nixpkgs-unstable
# 2026.10.1, so build 2026.10.3 from the nixpkgs-unstable package, which
# already has the Go 1.27.3 toolchain it needs (NixOS/nixpkgs#576762).
#
# Once the stable channel ships cloudflared >= 2026.10.3 (the backport,
# NixOS/nixpkgs#579392) this overlay becomes a no-op and emits a warning
# reminding to remove it.
#
# Requires the `unstable` overlay (pkgs.unstable) to be applied before this
# one in nixpkgs.overlays.
_final: prev:
let
  fixedVersion = "2026.10.3";
  noOverride = prev.lib.versionAtLeast prev.cloudflared.version fixedVersion;
  upstream = prev.unstable.cloudflared;

  pinned =
    if prev.lib.versionAtLeast upstream.version fixedVersion then
      upstream
    else
      upstream.overrideAttrs (finalAttrs: {
        version = fixedVersion;
        src = prev.fetchFromGitHub {
          owner = "cloudflare";
          repo = "cloudflared";
          tag = finalAttrs.version;
          hash = "sha256-k1OMkHHItOT5VHhQqgC8ODm/RCJEtwtZi0Lxyf/esLg=";
        };
      });
in
{
  cloudflared = prev.lib.warnIf noOverride ''
    cloudflared >= ${fixedVersion} is now in nixpkgs; the cloudflared-security overlay can be removed.
  '' (if noOverride then prev.cloudflared else pinned);
}
