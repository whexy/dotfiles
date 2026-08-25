# SSH configuration
args@{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
let
  osConfig = args.osConfig or null;
  cfg = config.dotfiles.ssh;
  isDarwin =
    if osConfig != null then
      lib.hasSuffix "-darwin" osConfig.dotfiles.host.system
    else
      pkgs.stdenv.hostPlatform.isDarwin;
  isWsl = osConfig != null && osConfig.dotfiles.host.wsl;

  # The WM owning the terminal-spawn keybinding owns window identity too.
  wmBackend =
    if isDarwin then
      config.dotfiles.wm.darwin.windowManager
    else if config.dotfiles.wm.niri.enable then
      "niri"
    else
      "auto";
in
{
  imports = [ inputs.oh-my-ghostty.homeModules.ssh-window ];

  options.dotfiles.ssh = {
    enable = lib.mkEnableOption "ssh";
    windowMultiplexing.enable = lib.mkEnableOption ''
      WM-scoped SSH terminal multiplexing (oh-my-ghostty): the wrapped ssh
      binds each Ghostty window to its SSH context, and `ssh-window launch`
      (bound to the WM's terminal-spawn key) opens context-inheriting
      terminals. Requires Ghostty and a supported window manager.
    '';
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.enable (
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
    ))
    (lib.mkIf (cfg.enable && cfg.windowMultiplexing.enable) {
      # Transport multiplexing lives here (not in the oh-my-ghostty module's
      # legacy matchBlocks) to match the settings-style ssh config above.
      # ControlPersist detaches the master, so closing the window that opened
      # a connection does not kill sessions in cloned windows.
      programs.ssh.settings."*" = {
        ControlMaster = "auto";
        ControlPath = "~/.ssh/control-%C";
        ControlPersist = "10m";
      };

      programs.ssh-window = {
        enable = true;
        configureControlMaster = false;
        backend = wmBackend;
      };
    })
  ];
}
