{ flake, ... }:
{
  dotfiles = {
    system.autoUpgrade.enable = true;
    power.alwaysOn.enable = true;
    services.openssh = {
      enable = true;
      hardened = true;
    };
    network = {
      # The T3 Code server publishes itself with `tailscale serve`.
      tailscale.userOperator = true;
      # The campus network leases only to this registered address.
      macAddresses.en0 = "90:09:d0:27:f6:fa";
      # Ethernet (en0) gives sheridan a public campus address; en1 is Wi-Fi.
      tailscaleOnly.interfaces = [
        "en0"
        "en1"
      ];
    };
  };

  imports = flake.lib.darwinHost {
    system = "aarch64-darwin";
    hostName = "sheridan";
    caps = [
      "base"
      "dev-lite"
      "gui"
    ];
    modules = [ ./hardware.nix ];
  };
}
