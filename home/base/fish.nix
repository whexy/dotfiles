# Shell configuration
{ pkgs, ... }:
{
  programs.fish = {
    enable = true;
  };

  programs.ssh = {
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
