# The iPhones agents can drive, each running WebDriverAgent on its own (see
# AGENTS.md, "iPhone automation"). `host` is the phone's MagicDNS name;
# `deviceName` is the name set on the phone (Settings > General > About >
# Name), which `iphone-wda` finds it by on a paired Mac.
{ flake }:
{
  iphone-17-pro = {
    host = flake.lib.tailnetHost "iphone-17-pro";
    deviceName = "Whexy Phone";
    description = "iPhone 17 Pro";
  };
}
