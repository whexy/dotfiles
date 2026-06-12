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

  system.stateVersion = "26.05";

  virtualisation = {
    cores = 16;
    memorySize = 32768;
    diskSize = 32768;
    graphics = false;

    qemu.package = pkgs.qemu_kvm;

    # forwardPorts = [
    #   {
    #     from = "host";
    #     host.port = 2222;
    #     guest.port = 22;
    #   }
    # ];

    # Share the NFS home into the guest over 9p for file access.
    sharedDirectories.hosthome = {
      source = "/home/wsk9140";
      target = "/host-home";
    };
  };

  # Disable password login.
  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = false;
  };

  # Serial console for `nix run` headless boot.
  boot.kernelParams = [ "console=ttyS0,115200" ];

  # Autologin on the serial console as a fallback if SSH is not yet up.
  services.getty.autologinUser = lib.mkDefault "whexy";
}
