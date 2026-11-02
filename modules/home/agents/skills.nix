# The skills every agent sees that no tool ships, as a `dotfiles.agents.skills`
# value; the home module and checks/agent-skills both take it from here.
{ flake, pkgs, ... }:
let
  inherit (pkgs) lib;
in
{
  # Written here, one directory each under ./skills.
  local = lib.mapAttrs (name: _: { source = ./skills + "/${name}"; }) (
    lib.filterAttrs (_: type: type == "directory") (builtins.readDir ./skills)
  );
  # Taken from the repositories under skills/ at the root of this repo.
  packages = lib.attrValues (flake.lib.skillRepos pkgs);
}
