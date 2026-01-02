{
  home-manager.users.whexy =
    { config, pkgs, ... }:
    {
      programs.ghostty = {
        enable = true;
        package = pkgs.ghostty-bin;

        settings = {
          # Theme
          theme = "Gruvbox Dark";

          # Fonts
          font-size = 16;
          font-family = "FiraCode Nerd Font";

          # Backgrounds
          background-opacity = 0.95;
          background-blur = true;

          # Window Sizes
          window-width = 160;
          window-height = 48;
          window-position-x = 320;
          window-position-y = 144;

          # MacOS workaround for Zellij
          macos-option-as-alt = "left";
          keybind = [
            "alt+left=unbind"
            "alt+right=unbind"
          ];
        };
      };
    };
}
