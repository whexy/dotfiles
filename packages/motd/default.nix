{ pkgs }:

# The build's flake8 skips what ruff (ruff.toml) owns or formats differently.
pkgs.writers.writePython3Bin "motd" {
  flakeIgnore = [
    "E203" # whitespace before ':' in slices
    "E501" # line length, which ruff checks at 100
    "W503" # line break before binary operator
  ];
} (builtins.readFile ./motd.py)
