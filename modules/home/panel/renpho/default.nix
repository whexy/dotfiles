# Renpho smart-scale data integration for the status bars.
#
# Measurements are published by the zepbound site as a JSON cache
# (https://zepbound.whexy.com/api/data.json) behind Cloudflare Access.
# Each selected bar runs ./weight.nix, which fetches only after the server's
# `sync.next_check_at` and otherwise reads its cache, authenticated with the
# shared CF Access service token.
{
  config,
  lib,
  ...
}:
{
  config = lib.mkIf config.dotfiles.panel.renpho.enable {
    dotfiles.cloudflareAccess.serviceToken.enable = true;
  };

  imports = [
    ./sketchybar.nix
    ./waybar.nix
    ./eww.nix
  ];
}
