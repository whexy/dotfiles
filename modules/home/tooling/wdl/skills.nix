# The change to wxstack's wdl skill where Nix installs wdl, as a
# `dotfiles.agents.skills` value; the home module and checks/agent-skills both
# take it from here.
_: {
  override = {
    wdl = {
      patches = [ ./wdl-skill.patch ];
      reason = ''
        The skill has agents npm-install the CLI into a directory of their
        own; here Nix installs wdl.
      '';
    };
  };
}
