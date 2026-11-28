{ inputs, pkgs, ... }:
{
  imports = [ inputs.self.homeModules.host-user ];

  dotfiles = {
    terminal.tmux.enable = true;
    vcs.git.command.enable = true;
    shell.motd.enable = true;
    editor.neovim.enable = true;
  };

  # `dotfiles.agents` installs every agent, 4 GiB of them, and its gateway
  # keys are secrets a tab cannot decrypt. Claude Code alone signs in with a
  # claude.ai login.
  home.packages = [ pkgs.llm-agents.claude-code ];

  # Its database of every package's files is a fifth of the image.
  programs.nix-index.enable = false;
  programs.man.enable = false;

  home.stateVersion = "26.05";
}
