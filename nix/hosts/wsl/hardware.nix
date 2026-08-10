{ lib, ... }:
{
  system.stateVersion = "25.11";

  # The dev cap enables NetworkManager, which pulls in wpa_supplicant.
  # WSL has no Wi-Fi hardware (Windows owns networking), so both are
  # useless here and wpa_supplicant fails on every activation switch.
  networking.networkmanager.enable = lib.mkForce false;

  wsl = {
    enable = true;
    defaultUser = "whexy";
    startMenuLaunchers = true;
    wslConf.automount.root = "/mnt";
    interop.register = true;
  };
}
