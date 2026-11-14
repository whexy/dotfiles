# The skills Modern Web Guidance ships, as a `dotfiles.agents.skills` value;
# the home module and checks/agent-skills both take it from here.
{ perSystem, ... }:
{
  packages = [ perSystem.self.modern-web-guidance ];
  override = {
    modern-web-guidance = {
      patches = [ ./modern-web-guidance-skill.patch ];
      reason = ''
        Upstream has agents fetch the CLI from npm on every run, which also
        sends usage telemetry; here Nix installs it with telemetry off, so
        it runs offline. It also has agents end each reply with a section
        on the guides they used.
      '';
    };
    chrome-extensions = {
      ignore = true;
      reason = ''
        The package also ships Chrome's extension-building skill, which
        agents here do not take.
      '';
    };
  };
}
