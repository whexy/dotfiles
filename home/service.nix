# Service home configuration
{ pkgs, ... }:
{
  home.packages = with pkgs; [
    # Network diagnostic tools
    dig
    fd
    nmap
    python3
    ripgrep
    traceroute
  ];
}
