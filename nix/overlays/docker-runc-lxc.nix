# Workaround: CVE-2025-52881 hardening breaks nested Docker inside LXC/Incus.
#
# runc >= 1.3.3 writes sysctls through a *detached* procfs mount to close a
# mount-race container escape. AppArmor names a detached mount as if it were
# mounted at "/", so writing /proc/sys/net/ipv4/ip_unprivileged_port_start is
# mediated as a write to /sys/net/ipv4/ip_unprivileged_port_start and denied by
# the "deny /sys/..." rules in the LXC container profile. Every container then
# fails at init with:
#
#   open sysctl net.ipv4.ip_unprivileged_port_start file: reopen fd 8: permission denied
#
# The guest cannot repair this: the profile is generated and applied by the
# Incus host, AppArmor "deny" rules cannot be overridden from inside the
# container, and there is no raw.apparmor escape hatch for this one. Pre-setting
# the sysctl on the guest does not help either, because runc writes it
# unconditionally. crun fails the same way, so switching runtimes is not a way
# out.
#
# So pin runc to 1.3.2, the last release before the hardening, as upstream
# recommends for those who must downgrade. Do NOT go older: 1.3.2 still carries
# every earlier fix, while runc 1.1.x is unsupported and adds CVE-2024-45310.
# The bundled runc is what dockerd executes; pkgs.runc is a different package
# and overriding it has no effect, so the pin goes through docker's own args.
#
# Trade-off: these hosts stay exposed to CVE-2025-52881 and its two sibling
# escapes. Acceptable only because they run trusted, first-party workloads.
# Do not apply this overlay where untrusted images or `docker build` input run.
#
# Removal is gated on the Incus *host*, not on nixpkgs: the fix is lxc/incus#2624,
# released in Incus 6.0.6 and 6.19. These hosts run Incus 6.0, and upgrading it
# requires a newer kernel than we control. Newer nixpkgs only ships newer runc,
# which keeps the breakage, so there is nothing to detect from inside Nix.
# Drop this overlay (and the host `overlays = [ ... ]` entries) once the host is
# on Incus >= 6.0.6.
#
# References:
#   https://github.com/opencontainers/runc/issues/4968
#   https://github.com/lxc/incus/issues/2623
#   https://github.com/lxc/incus/pull/2624
_final: prev: {
  docker = prev.docker.override {
    runcRev = "v1.3.2";
    runcHash = "sha256-Yva0zrcnuHCuIYVi07sxTxNc4fOXVo93jO1hbHjdYNo=";
  };
}
