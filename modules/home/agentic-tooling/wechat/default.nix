{
  config,
  lib,
  pkgs,
  perSystem,
  ...
}:
{
  config = lib.mkIf config.dotfiles.agenticTooling.wechat.enable {
    home.packages = [ perSystem.self.wechat-cli ];
    dotfiles.agents.skills = import ./skills.nix { inherit pkgs perSystem; };
  };
}
