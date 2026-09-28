# macOS-specific system configuration
_: {
  dotfiles.hardware = {
    headless = true;
    keyboards = [
      {
        vendorId = 12815;
        productId = 20565;
        isPointingDevice = true;
        description = "VGN V98pro BT1";
      }
    ];
  };

  # Turn off an attached display after 1 hour idle.
  power.sleep.display = 60;
}
