# Self-expiring overlay: Tailscale < 1.102.1 has a security vulnerability,
# but the pinned stable nixpkgs only ships 1.98.x, so pull tailscale from
# nixpkgs-unstable until the stable channel catches up.
#
# Once the stable channel ships tailscale >= 1.102.1 this overlay becomes a
# no-op and emits a warning reminding to remove it.
#
# Requires the `unstable` overlay (pkgs.unstable) to be applied before this
# one in nixpkgs.overlays.
_final: prev:
let
  fixedVersion = "1.102.1";
  noOverride = prev.lib.versionAtLeast prev.tailscale.version fixedVersion;
in
{
  tailscale = prev.lib.warnIf noOverride ''
    tailscale >= ${fixedVersion} is now in nixpkgs; the tailscale-security overlay can be removed.
  '' (if noOverride then prev.tailscale else prev.unstable.tailscale);
}
