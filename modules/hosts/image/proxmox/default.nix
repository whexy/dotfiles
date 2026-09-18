# Proxmox image/runtime fallback settings.
{ lib, ... }:
{
  options.dotfiles.image.proxmox.enable = lib.mkEnableOption "Proxmox VM image defaults";
}
