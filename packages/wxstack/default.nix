# Our published skills, every one of them.
{
  flake,
  pkgs,
  pname,
}:
flake.lib.skillRepo {
  inherit pkgs pname;
  owner = "whexy";
  repo = "wxstack";
  pins = ./sources.json;
}
