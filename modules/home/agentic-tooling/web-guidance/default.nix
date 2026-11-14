{
  config,
  lib,
  pkgs,
  perSystem,
  flake,
  ...
}:
{
  config = lib.mkIf config.dotfiles.agenticTooling.webGuidance.enable {
    home.packages = [ perSystem.self.modern-web-guidance ];
    dotfiles.agents.skills = import ./skills.nix { inherit pkgs perSystem flake; };
  };
}
