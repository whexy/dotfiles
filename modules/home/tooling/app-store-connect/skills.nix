# The asc skill, as a `dotfiles.agents.skills` value; the home module and
# checks/agent-skills both take it from here.
_: {
  local.asc = {
    source = ./skill;
    reason = ''
      Points at the guides asc prints, which match the installed
      version, instead of the skill pack `asc install-skills` would copy
      in at runtime.
    '';
  };
}
