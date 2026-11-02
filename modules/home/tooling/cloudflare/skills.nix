# The skills cf ships, as a `dotfiles.agents.skills` value; the home module
# and checks/agent-skills both take it from here.
{ perSystem, ... }:
{
  packages = [ perSystem.self.cf ];
  override = {
    cf-cli = {
      patches = [ ./cf-cli-skill.patch ];
      reason = ''
        Cloudflare's install and sign-in steps would have agents run
        `npm install --global cf` and `cf auth login`; here Nix installs
        cf and it signs in with the agenix token.
      '';
    };
  };
}
