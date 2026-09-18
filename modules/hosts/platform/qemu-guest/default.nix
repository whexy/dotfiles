# QEMU guest with UEFI boot and a Disko-managed system disk.
{ lib, ... }:
{
  options.dotfiles.platform.qemuGuest.enable =
    lib.mkEnableOption "the QEMU UEFI guest platform with Disko";
}
