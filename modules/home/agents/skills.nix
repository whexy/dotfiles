# The skills written in this repository for every agent, one directory each
# under ./skills, as a `dotfiles.agents.skills` value; the home module and
# checks/agent-skills both take it from here.
{ pkgs, ... }:
let
  inherit (pkgs) lib;
in
{
  local = lib.mapAttrs (name: _: { source = ./skills + "/${name}"; }) (
    lib.filterAttrs (_: type: type == "directory") (builtins.readDir ./skills)
  );
}
