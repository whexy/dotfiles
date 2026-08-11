# Renpho smart-scale integration (Linux + gui only).
#
# Wires the renpho-health flake's home-manager modules to:
#   - the agenix-encrypted credentials file (RENPHO_EMAIL / RENPHO_PASSWORD)
#   - a systemd user timer that refreshes the JSON cache every hour
#   - a waybar pill that displays weight + trend from the cache
#
# Note: the renpho-health home-manager modules are imported by ./default.nix
# (this file is gated on dotfiles.panel.renpho and cannot declare imports).
args@{
  config,
  lib,
  ...
}:
let
  osConfig = args.osConfig or null;
  cfg = config.dotfiles.panel;
  isDarwin = osConfig != null && lib.hasSuffix "-darwin" osConfig.dotfiles.host.system;
in
{
  config = lib.mkIf (cfg.renpho.enable && !isDarwin) {
    age.secrets.renpho-creds.file = ../../../../secrets/renpho-creds.age;

    services.renpho-health = {
      enable = true;
      credsFile = config.age.secrets.renpho-creds.path;
    };

    programs.waybar.renpho.enable = true;
  };
}
