# Dev NixOS system configuration
{ ... }:
{
  time.timeZone = "America/Chicago";
  programs.zsh.enable = true;
  security.sudo.wheelNeedsPassword = false;

  # Dev services
  networking.networkmanager.enable = true;
  services.openssh.enable = true;
  services.tailscale.enable = true;
  virtualisation.docker.enable = true;
  programs.nix-ld.enable = true;
}
