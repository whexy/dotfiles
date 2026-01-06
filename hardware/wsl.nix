{
  system.stateVersion = "25.11";

  wsl = {
    enable = true;
    defaultUser = "whexy";
    startMenuLaunchers = true;
    wslConf.automount.root = "/mnt";
  };
}
