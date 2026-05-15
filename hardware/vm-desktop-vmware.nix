# Hardware config for VMware VM images
# Supports both x86_64 and aarch64 architectures
# Build image with: just build-desktop vmware [x86_64|aarch64]
{
  lib,
  pkgs,
  ...
}:

{
  imports = [
    ./vm-desktop-base.nix
  ];

  # Configure the VMware image module
  image.modules.vmware = {
    # Auto-size disk based on closure
    vmware.baseImageSize = "auto";

    # Sparse format good for development
    vmware.vmSubformat = "monolithicSparse";

    # VMware guest support (image-specific)
    virtualisation.vmware.guest = {
      enable = true;
      headless = false; # Enable GUI/Wayland features
    };
  };

  # VMware guest tools for the running system
  virtualisation.vmware.guest = {
    enable = true;
    headless = false;
  };

  # Networking for VMware guests.
  #
  # The dev cap enables NetworkManager. On this hardware, NM + raw
  # /etc/resolv.conf conflicts with Tailscale: both try to own the resolver.
  #
  # NixOS enable firewall by default. Since VMs are behind the NAT on host, host
  # is the only machine that can access the VM. We allow host to access guest
  # network to make dev easier.
  networking = {
    networkmanager.enable = lib.mkForce false;
    useNetworkd = true;
    useDHCP = false;
    firewall.enable = lib.mkForce false;
  };

  systemd.network = {
    enable = true;
    networks."10-wired" = {
      matchConfig.Type = "ether";
      networkConfig = {
        DHCP = "yes";
        IPv6AcceptRA = true;
      };
    };
  };

  services.resolved = {
    enable = true;
    # Tailscale MagicDNS responses are not DNSSEC-signed; disabling avoids
    # spurious SERVFAILs on tailnet lookups.
    dnssec = "false";
    # Workaround for unreliable VMware host DNS — used only when the link's
    # DHCP-supplied DNS returns nothing, so it does not override Tailscale.
    fallbackDns = [
      "1.1.1.1"
      "8.8.8.8"
    ];
  };

  # Kernel modules for VMware
  boot = {
    initrd.availableKernelModules = [
      "mptspi" # SCSI controller
      "ahci" # SATA controller
      "sd_mod" # SCSI disk
      "sr_mod" # SCSI CD-ROM
    ];

    # x86-only paravirtualized SCSI driver
    initrd.kernelModules = lib.optionals pkgs.stdenv.hostPlatform.isx86 [
      "vmw_pvscsi" # Paravirtualized SCSI
    ];

    kernelModules = [
      "vmw_balloon" # Memory ballooning
      "vmw_vmci" # Guest-host communication
    ];
  };
}
