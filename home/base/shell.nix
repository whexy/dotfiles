# Shell configuration
{ lib, ... }:
{
  programs.zsh = {
    enable = true;
    enableCompletion = true;

    history = {
      save = 10000;
      size = 10000;
      share = true;
    };
  };

  programs.ssh = lib.mkDefault {
    enable = true;
    enableDefaultConfig = false;
    # HM 26.05 deprecated `matchBlocks`; entries now live under `settings`
    # using OpenSSH directive names directly (no `extraOptions` wrapper).
    settings = {
      "*" = {
        AddKeysToAgent = "yes";
      };
    };
  };
}
