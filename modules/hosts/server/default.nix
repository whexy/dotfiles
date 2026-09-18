# Server group: internet-facing host hygiene.
{ lib, ... }:
{
  options.dotfiles.server = {
    enable = lib.mkEnableOption ''
      internet-facing server essentials (resolved, timesyncd, bounded
      journald logs, HTTP/HTTPS/SSH firewall ports)'';
  };
}
