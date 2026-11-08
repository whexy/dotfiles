{ pkgs }:
pkgs.writeShellApplication {
  name = "github-app-token";
  runtimeInputs = [
    pkgs.coreutils
    pkgs.curl
    pkgs.jq
    pkgs.openssl
  ];
  text = builtins.readFile ./github-app-token.sh;
}
