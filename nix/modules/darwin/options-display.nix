{ lib, ... }:
{
  options.hardware.display = {
    macbookScreen = lib.mkEnableOption ''
      this machine is running on a MacBook Retina panel.
    '';
  };
}
