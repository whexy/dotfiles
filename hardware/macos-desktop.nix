# macOS-specific system configuration
_: {
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

  # pmset settings not covered by nix-darwin's power module:
  # - sleep 0: disable system sleep timer (belt-and-suspenders with systemsetup)
  # - powernap 0: disable Power Nap, which can suspend network interfaces
  # - ttyskeepawake 1: stay awake while any remote session (SSH/Tailscale) is active
  # - womp 1: wake on ethernet magic packet (remote wakeup)
  system.activationScripts.powerManagement.text = ''
    echo "Configuring pmset for always-on server mode..."
    /usr/bin/pmset -a sleep 0
    /usr/bin/pmset -a powernap 0
    /usr/bin/pmset -a ttyskeepawake 1
    /usr/bin/pmset -a womp 1
  '';
}
