# The skills every agent sees that no tool ships, as a `dotfiles.agents.skills`
# value; the home module and checks/agent-skills both take it from here.
{ pkgs, perSystem, ... }:
let
  inherit (pkgs) lib;
in
{
  # Written here, one directory each under ./skills.
  local = lib.mapAttrs (name: _: { source = ./skills + "/${name}"; }) (
    lib.filterAttrs (_: type: type == "directory") (builtins.readDir ./skills)
  );
  # The skill repositories every agent takes, built with the caller's pkgs:
  # a Darwin home's is nixpkgs-darwin, not the flake's packages set.
  packages = map (repo: repo.override { inherit pkgs; }) [
    perSystem.self.tstack
    perSystem.self.wxstack
  ];
}
