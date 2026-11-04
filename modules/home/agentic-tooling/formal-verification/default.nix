# Formal verification. Agents verify the code where a bug costs most and
# leave a project-local skill that reruns the check, reaching first for TLA+
# models, which statechart reads back as paths through states.
{
  config,
  lib,
  pkgs,
  perSystem,
  ...
}:
let
  cfg = config.dotfiles.agenticTooling.formalVerification;
in
{
  config = lib.mkIf cfg.enable {
    home.packages = [ pkgs.tlaplus ];
    dotfiles.agents.skills = import ./skills.nix { inherit perSystem; };
  };
}
