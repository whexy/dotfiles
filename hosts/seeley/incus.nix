# Incus host for the clusters-work node k8s-7, a VM that leaves with this
# machine by 2027. The guest bridge, NAT-PMP responder and firewall follow
# venus and mars (clusters-work docs/networking.md, "Incus hosts"): the guest
# runs tailscaled on its own pinned port behind this host's masquerade and
# leases that port here, so peers without a port mapping of their own still
# reach it directly.
let
  bridge = "incusbr0";
  subnet = "10.77.0.0/24";
  uplink = "enp0s31f6";
in
{
  virtualisation.incus.preseed = {
    networks = [
      {
        name = bridge;
        type = "bridge";
        config = {
          "ipv4.address" = "10.77.0.1/24";
          "ipv4.nat" = "true";
          "ipv6.address" = "none";
        };
      }
    ];
    storage_pools = [
      {
        name = "default";
        driver = "dir";
        config.source = "/var/lib/incus-pool";
      }
    ];
    profiles = [
      {
        name = "default";
        devices = {
          eth0 = {
            name = "eth0";
            network = bridge;
            type = "nic";
          };
          root = {
            path = "/";
            pool = "default";
            type = "disk";
          };
        };
      }
    ];
  };

  # VM disks are raw image files, and the OSD disk takes random writes:
  # nodatacow (+C, inherited by new files) keeps btrfs from fragmenting them.
  # It also turns off compression and checksums for those files only.
  systemd.tmpfiles.rules = [
    "d /var/lib/incus-pool 0711 root root -"
    "h /var/lib/incus-pool - - - - +C"
  ];

  # DHCP and DNS from the bridge's dnsmasq, and NAT-PMP from miniupnpd.
  networking.firewall.interfaces.${bridge} = {
    allowedUDPPorts = [
      53
      67
      5351
    ];
    allowedTCPPorts = [ 53 ];
  };

  services.miniupnpd = {
    enable = true;
    externalInterface = uplink;
    internalIPs = [ bridge ];
    natpmp = true;
    upnp = false;
    appendConfig = ''
      allow 1024-65535 ${subnet} 1024-65535
      deny 0-65535 0.0.0.0/0 0-65535
    '';
  };
}
