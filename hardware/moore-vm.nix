# Hardware profile for the `moore` server dev VM.
#
# This profile is consumed by NixOS's `config.system.build.vm` builder
# (the `nixos-rebuild build-vm` engine). It boots a headless VM whose
# /nix/store is shared read-only from the host over 9p, with a writable
# scratch disk for `/`.
#
# On `moore` we are an unprivileged user running nix via nix-portable
# (bwrap). KVM is available: /dev/kvm is world rw and the host CPU has vmx.
#
# Run it with the generated launcher, pointing the scratch disk at local
# /tmp (home is slow NFS):
#
#   export NIX_DISK_IMAGE=/tmp/moore-vm-$USER.qcow2
#   nix run .#nixosConfigurations.moore.config.system.build.vm
#
# Then SSH into the guest:
#
#   ssh -p 2222 whexy@localhost
{
  pkgs,
  lib,
  modulesPath,
  ...
}:

{
  imports = [
    # Provides `virtualisation.*` options and `config.system.build.vm`.
    (modulesPath + "/virtualisation/qemu-vm.nix")
  ];

  system.stateVersion = "25.11";

  virtualisation = {
    # Resources (host has 48 cores / 251 GB RAM).
    cores = 8;
    memorySize = 16384;

    # Writable scratch disk size for `/`. Lives on /tmp via NIX_DISK_IMAGE.
    diskSize = 8192;

    # Headless: serial console only.
    graphics = false;

    # Use a Nix-managed qemu so we do not depend on the host qemu for the
    # first run. KVM acceleration is enabled by the generated launcher.
    qemu.package = pkgs.qemu_kvm;

    # SSH into the guest from the host: host 2222 -> guest 22.
    forwardPorts = [
      {
        from = "host";
        host.port = 2222;
        guest.port = 22;
      }
    ];

    # Share the NFS home into the guest over 9p for file access.
    sharedDirectories.hosthome = {
      source = "/home/wsk9140";
      target = "/host-home";
    };
  };

  # Allow password SSH login (user has a hashedPassword set).
  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = lib.mkDefault true;
  };

  # Serial console for `nix run` headless boot.
  boot.kernelParams = [ "console=ttyS0,115200" ];

  # Autologin on the serial console as a fallback if SSH is not yet up.
  services.getty.autologinUser = lib.mkDefault "whexy";
}
