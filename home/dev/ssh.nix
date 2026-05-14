# SSH configuration
{
  lib,
  darwin ? false,
  wsl ? false,
  ...
}:
let
  identityAgent =
    if darwin then
      "\"~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock\""
    else
      "~/.1password/agent.sock";
in
{
  # On WSL, ssh is aliased to ssh.exe which uses Windows SSH config,
  # so this config is only relevant for native Linux and macOS
  programs.ssh = {
    enable = !wsl;
    enableDefaultConfig = false;

    matchBlocks = {
      "*" = {
        inherit identityAgent;
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
