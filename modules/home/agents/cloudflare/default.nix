{
  config,
  lib,
  pkgs,
  perSystem,
  ...
}:
{
  config = lib.mkIf (config.dotfiles.agents.enable && config.dotfiles.tooling.cloudflare.cli.enable) {
    dotfiles.agents.skills = import ./skills.nix { inherit pkgs perSystem; };
  };
}
