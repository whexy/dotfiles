{ inputs, ... }:
{
  imports = [ inputs.self.homeModules.host-user ];

  dotfiles = {
    panel.linuxBar = "eww";
    # Only this host: Ghidra brings REA's closure to about 2 GiB.
    agenticTooling.rea = {
      enable = true;
      browser.enable = true;
      android.enable = true;
      binary.enable = true;
      firmware.enable = true;
      javascript.enable = true;
      networkCapture.enable = true;
      dotnet.enable = true;
    };
  };

  home.stateVersion = "26.05";
}
