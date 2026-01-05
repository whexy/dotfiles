# macOS-specific system configuration
{ ... }:
{
  # Power settings: save battery life
  power = {
    sleep = {
      computer = 15; # sleep after 15 minutes idle
      display = 10; # turn off display after 10 minutes idle
    };
  };
}
