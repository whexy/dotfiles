{
  flake,
  pkgs,
  pname,
}:
flake.lib.skillRepo {
  inherit pkgs pname;
  owner = "t3dotgg";
  repo = "tstack";
  skills = [ "sol-loop" ];
  pins = ./sources.json;
}
