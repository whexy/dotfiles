{ inputs, pkgs, ... }:
{
  imports = [ inputs.self.homeModules.host-user ];

  dotfiles = {
    terminal.tmux.enable = true;
    vcs.git.command.enable = true;
    shell.motd.enable = true;
    editor.neovim.enable = true;
    # The desktop without the gui cap: niri and Ghostty alone.
    wm.niri = {
      enable = true;
      idleLock.enable = false;
    };
    # No lock screen or tray applets.
    desktop.session.enable = false;
    terminal.ghostty.enable = true;
  };

  # Ghostty needs OpenGL 4.3 and the tab's GPU offers 2.1, so Ghostty alone
  # renders on the CPU.
  xdg.configFile."systemd/user/app-com.mitchellh.ghostty.service.d/software-gl.conf".text = ''
    [Service]
    Environment=LIBGL_ALWAYS_SOFTWARE=1
  '';

  # `dotfiles.agents` installs every agent, 4 GiB of them, and its gateway
  # keys are secrets a tab cannot decrypt. Claude Code alone signs in with a
  # claude.ai login.
  home.packages = [ pkgs.llm-agents.claude-code ];

  # Its database of every package's files is a fifth of the image.
  programs.nix-index.enable = false;
  programs.man.enable = false;

  home.stateVersion = "26.05";
}
