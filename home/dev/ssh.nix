# SSH configuration
{ pkgs, ... }:
{
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;

    matchBlocks = {
      "*" = {
        identityAgent =
          if pkgs.stdenv.isDarwin
          then "\"~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock\""
          else "~/.1password/agent.sock";
        forwardAgent = true;
        serverAliveInterval = 25;
        serverAliveCountMax = 3;
      };

      "mars" = {
        hostname = "mars.cs.northwestern.edu";
        user = "wenxuan";
      };

      "venus" = {
        hostname = "venus.cs.northwestern.edu";
        user = "wenxuan";
      };

      "moore" = {
        hostname = "moore.wot.eecs.northwestern.edu";
        user = "wsk9140";
      };
    };
  };
}
