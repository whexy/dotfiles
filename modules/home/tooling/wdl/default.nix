# wdl, the CLI for Workers on a self-hosted WDL platform. Credentials stay
# with the CLI's own token store (`wdl token set`), per namespace.
{
  config,
  lib,
  pkgs,
  perSystem,
  flake,
  ...
}:
{
  config = lib.mkIf config.dotfiles.tooling.wdl.enable {
    home.packages = [ perSystem.self.wdl ];
    dotfiles.agents.skills = import ./skills.nix { inherit pkgs perSystem flake; };
  };
}
