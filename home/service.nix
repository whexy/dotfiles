# Service home configuration
{ pkgs, ... }:
{
  home.packages = with pkgs; [
    # Network diagnostic tools
    curl
    wget
    openssl
    dig
    traceroute
    nmap
    tcpdump
    mtr

    # process/fs
    btop
    lsof
    strace
    duf
    ncdu

    # text/search
    ripgrep
    fd
    jq
    yq-go

    # ops
    git
    rsync

    # scripting
    python3
  ];
}
