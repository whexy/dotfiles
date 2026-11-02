# REA's skills, as a `dotfiles.agents.skills` value; the home module and
# checks/agent-skills both take it from here.
{ perSystem, ... }:
{
  # Taken from the package so the instructions match the server's tools.
  packages = [ perSystem.self.rea-agents ];
}
