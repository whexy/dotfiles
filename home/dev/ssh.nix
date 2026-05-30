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

    # HM 26.05 deprecated `matchBlocks`; entries now live under `settings`
    # and use OpenSSH directive names (camelCase aliases dropped).
    settings = {
      "*" = {
        IdentityAgent = identityAgent;
        ForwardAgent = true;
        ServerAliveInterval = 25;
        ServerAliveCountMax = 3;
      };

      "mars" = {
        HostName = "mars.cs.northwestern.edu";
        User = "wenxuan";
      };

      "venus" = {
        HostName = "venus.cs.northwestern.edu";
        User = "wenxuan";
      };

      "moore" = {
        HostName = "moore.wot.eecs.northwestern.edu";
        User = "wsk9140";
      };
    };
  };
}
