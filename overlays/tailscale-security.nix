# Self-expiring overlay: Tailscale < 1.104.4 has security vulnerabilities in
# Tailscale SSH and Serve (TS-2026-014 through TS-2026-017). The NixOS stable
# channel already ships the fix, but nixpkgs-darwin still has 1.98.x, so pull
# tailscale from nixpkgs-unstable until that channel catches up.
#
# On a channel that ships tailscale >= 1.104.4 this overlay is a no-op and
# warns that it can be removed; remove it once Darwin evaluations warn too.
#
# Requires the `unstable` overlay (pkgs.unstable) to be applied before this
# one in nixpkgs.overlays.
_final: prev:
let
  fixedVersion = "1.104.4";
  noOverride = prev.lib.versionAtLeast prev.tailscale.version fixedVersion;
in
{
  tailscale = prev.lib.warnIf noOverride ''
    tailscale >= ${fixedVersion} is now in nixpkgs; the tailscale-security overlay can be removed.
  '' (if noOverride then prev.tailscale else prev.unstable.tailscale);
}
