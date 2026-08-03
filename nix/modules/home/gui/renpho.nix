# Renpho smart-scale integration (Linux + gui only).
#
# Wires the renpho-health flake's home-manager modules to:
#   - the agenix-encrypted credentials file (RENPHO_EMAIL / RENPHO_PASSWORD)
#   - a systemd user timer that refreshes the JSON cache every hour
#   - a waybar pill that displays weight + trend from the cache
#
# Darwin gui hosts (mba, mini) import this file too, but the renpho-health
# modules are themselves `lib.mkIf isLinux`, so this whole stack becomes a
# no-op there. We still guard the agenix secret declaration with `!darwin`
# because the .age file location and decryption flow differ on macOS and
# we have no consumer for it there.
{
  inputs,
  config,
  lib,
  darwin,
  ...
}:

{
  imports = [
    inputs.renpho-health.homeModules.default
    inputs.renpho-health.homeModules.waybar
  ];

  config = lib.mkIf (!darwin) {
    age.secrets.renpho-creds.file = ../../../../secrets/renpho-creds.age;

    services.renpho-health = {
      enable = true;
      credsFile = config.age.secrets.renpho-creds.path;
    };

    programs.waybar.renpho.enable = true;
  };
}
