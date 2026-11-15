{
  flake,
  pkgs,
  pname,
}:
flake.lib.skillRepo {
  inherit pkgs pname;
  owner = "ChenLiu-1996";
  repo = "figures4papers";
  pins = ./sources.json;
}
