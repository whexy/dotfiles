{ pkgs }:

pkgs.writers.writePython3Bin "motd" {
  flakeIgnore = [
    "E501" # long lines
    "W503" # line break before binary operator
  ];
} (builtins.readFile ./motd.py)
