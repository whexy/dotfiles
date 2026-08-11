# SSH configuration
args@{
  config,
  lib,
  ...
}:
let
  osConfig = args.osConfig or null;
  cfg = config.dotfiles.ssh;
  isDarwin = osConfig != null && lib.hasSuffix "-darwin" osConfig.dotfiles.host.system;
  isWsl = osConfig != null && osConfig.dotfiles.host.wsl;

  # Whether this host is on the tailnet (null osConfig = standalone home,
  # which is off the tailnet).
  tailscale = osConfig != null && osConfig.dotfiles.network.tailscale.enable;
in
{
  options.dotfiles.ssh.enable = lib.mkEnableOption "ssh";

  config = lib.mkIf cfg.enable (
    let
      identityAgent =
        if isDarwin then
          "\"~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock\""
        else
          "~/.1password/agent.sock";
    in
    {
      # On WSL, ssh is aliased to ssh.exe which uses Windows SSH config,
      # so this config is only relevant for native Linux and macOS
      programs.ssh = {
        enable = !isWsl;
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

          # "remote-dev" is a MagicDNS name on the tailnet; only reachable with Tailscale.
          "dev" = lib.mkIf tailscale {
            HostName = "remote-dev";
            User = "whexy";
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
  );
}
