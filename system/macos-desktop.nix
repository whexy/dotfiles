# macOS-specific system configuration
{ ... }:
{
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
