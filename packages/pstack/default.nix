{
  flake,
  pkgs,
  pname,
}:
flake.lib.skillRepo {
  inherit pkgs pname;
  owner = "cursor";
  repo = "plugins";
  # ketchup borrows bro's voice through a relative link to ../bro.
  skills = [
    "bro"
    "ketchup"
  ];
  pins = ./sources.json;
  alsoBuild = [ "formal-verification" ];
}
