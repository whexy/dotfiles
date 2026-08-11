# Audio NixOS configuration: PipeWire with PulseAudio + ALSA compatibility
# shims and WirePlumber as the session manager. Required by the waybar audio
# module (wpctl) and by any desktop app that produces sound.
# Host-specific extensions (e.g. RAOP/AirPlay discovery on ord) live in
# the corresponding host configuration.
{ config, lib, ... }:
let
  cfg = config.dotfiles.audio;
in
{
  config = lib.mkIf cfg.enable {
    services.pulseaudio.enable = false;
    security.rtkit.enable = true;
    services.pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
      wireplumber = {
        enable = true;
        extraConfig."51-bluez-headphones" = {
          "monitor.bluez.properties"."bluez5.roles" = [
            "a2dp_source"
            "hsp_ag"
            "hfp_ag"
          ];
          "monitor.bluez.rules" = [
            {
              matches = [ { "device.name" = "~bluez_card.*"; } ];
              actions.update-props."bluez5.auto-connect" = [
                "a2dp_source"
                "hsp_ag"
                "hfp_ag"
              ];
            }
          ];
        };
      };
    };
  };
}
