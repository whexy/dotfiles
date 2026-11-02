# The skills iPhone Use ships, as a `dotfiles.agents.skills` value; the home
# module and checks/agent-skills both take it from here.
{ perSystem, ... }:
{
  packages = [ perSystem.self.iphone-use ];
  override.iphone-use-setup = {
    replace = ./iphone-use-setup;
    reason = ''
      Upstream's setup skill builds and starts WebDriverAgent with
      xcodebuild on one USB phone; here phones run it on their own and
      are chosen per session. The usage skill links to it by this name.
    '';
  };
}
