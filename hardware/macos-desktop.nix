# macOS-specific system configuration
{ ... }:
{
  hardware.keyboards = [
    {
      vendorId = 12815;
      productId = 20565;
      isPointingDevice = true;
      description = "VGN V98pro BT1";
    }
  ];

  # Power settings: disable sleep, auto restart after power failure
  power = {
    restartAfterPowerFailure = true;
    restartAfterFreeze = true;
    sleep = {
      computer = "never"; # never go to sleep
      display = 60; # turn off display after 1 hour idle
    };
  };
}
