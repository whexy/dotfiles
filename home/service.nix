# Service home configuration
{ pkgs, ... }:
{
  home.packages = with pkgs; [
    # Network diagnostic tools
    dig
    fd
    nmap
    ripgrep
    traceroute
  ];
}
