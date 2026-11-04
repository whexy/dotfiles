# The formal-verification skills, as a `dotfiles.agents.skills` value; the
# home module and checks/agent-skills both take it from here.
{ perSystem, ... }:
{
  packages = [ perSystem.self.formal-verification ];
}
