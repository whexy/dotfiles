{ lib, ... }:
{
  system.stateVersion = "25.11";

  # The dev cap enables the network basics preset. WSL has no Wi-Fi
  # hardware (Windows owns networking), so NetworkManager/wpa_supplicant
  # are unnecessary and wpa_supplicant fails on every activation switch.
  dotfiles.network.basics.enable = lib.mkForce false;

  wsl = {
    enable = true;
    defaultUser = "whexy";
    startMenuLaunchers = true;
    wslConf.automount.root = "/mnt";
    interop.register = true;
  };
}
