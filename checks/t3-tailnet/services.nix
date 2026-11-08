# modules/home/t3code/services.nix for either platform, as the T3 checks call
# it: what a check does not exercise is fixed here.
{ pkgs, flake }:
isDarwin: args:
import ../../modules/home/t3code/services.nix (
  {
    inherit pkgs isDarwin;
    inherit (pkgs) lib;
    inherit (flake.lib.t3) port tailnetPort;
    cfg.server = {
      enable = true;
      tailnet.enable = true;
    };
    gitConfig = "/dev/null";
  }
  // args
)
