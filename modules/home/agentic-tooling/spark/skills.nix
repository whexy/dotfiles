# Spark's skill, as a `dotfiles.agents.skills` value; the home module and
# checks/agent-skills both take it from here.
_: {
  local.spark = {
    source = ./skill;
    reason = ''
      The search-and-read part of `spark skill` from Spark 1.4.1, which
      Spark Desktop prints at runtime and no package ships. Compare
      against a newer CLI's output when its commands change.
    '';
  };
}
