# Network diagnostic tools.
{
  config,
  pkgs,
  lib,
  ...
}:
{
  config = lib.mkIf config.dotfiles.tooling.network.enable {
    home.packages =
      with pkgs;
      [
        dig
        iperf3
        mtr
        nmap
        openssl
        socat
        tcpdump
      ]
      ++ lib.optionals pkgs.stdenv.isLinux [
        traceroute
      ];
  };
}
