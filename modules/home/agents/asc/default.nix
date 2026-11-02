{ config, lib, ... }:
{
  config =
    lib.mkIf (config.dotfiles.agents.enable && config.dotfiles.tooling.appStoreConnect.enable)
      {
        dotfiles.agents.skills.local.asc = {
          source = ./skill;
          reason = ''
            Points at the guides asc prints, which match the installed
            version, instead of the skill pack `asc install-skills` would copy
            in at runtime.
          '';
        };
      };
}
