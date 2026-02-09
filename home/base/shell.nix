# Shell configuration
{ lib, pkgs, ... }:
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
    matchBlocks = {
      "*" = {
        extraOptions = {
          AddKeysToAgent = "yes";
        };
      };
    };
  };
}
