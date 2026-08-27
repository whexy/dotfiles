# Renpho smart-scale data integration for the status bars.
#
# Measurements are published by the zepbound site as a JSON cache
# (https://zepbound.whexy.com/api/data.json) behind Cloudflare Access.
# Each selected bar fetches it directly on its own interval, authenticated
# with the shared CF Access service token (see modules/home/rclone for the
# header mechanics).
{
  config,
  lib,
  ...
}:
{
  config = lib.mkIf config.dotfiles.panel.renpho.enable {
    age.secrets = {
      cf-access-dotfiles-id.file = ../../../../../secrets/cf-access-dotfiles-id.age;
      cf-access-dotfiles-secret.file = ../../../../../secrets/cf-access-dotfiles-secret.age;
    };
  };

  imports = [
    ./sketchybar.nix
    ./waybar.nix
    ./eww.nix
  ];
}
