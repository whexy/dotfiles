# Wezterm terminal configuration
{
  programs.wezterm = {
    enable = true;
    enableBashIntegration = true;
    enableZshIntegration = true;
    extraConfig = builtins.readFile ./wezterm/wezterm.lua;
  };
}
