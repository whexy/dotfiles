# Minimal shell configuration for all hosts
{
  imports = [
    ./base/shell.nix
    ./base/tmux.nix
    ./base/vim.nix
  ];

  home-manager.users.whexy = {
    home.stateVersion = "25.11";
  };
}
