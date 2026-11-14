{
  flake,
  pkgs,
  pname,
}:
flake.lib.skillRepo {
  inherit pkgs pname;
  owner = "GoogleChrome";
  repo = "modern-web-guidance";
  skills = [ "modern-web-guidance" ];
  pins = ./sources.json;
}
