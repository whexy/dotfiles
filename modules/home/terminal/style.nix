# Font and color themes shared by the terminal emulators and Neovide, so that
# they look like Ghostty. Theme names are files in Ghostty's themes directory.
{
  font = "FiraCode Nerd Font";
  fontSize = macbookScreen: if macbookScreen then 16 else 14;
  opacity = 0.9;
  darkTheme = "Gruvbox Dark";
  # lightTheme = "Catppuccin Latte";
  lightTheme = "Gruvbox Light";

  # Nostalgia mode: `ghostty-nostalgia` creates this file and `ghostty-modern`
  # removes it, then both send the signal to every Neovim, which re-reads it.
  nostalgia = {
    file = stateHome: "${stateHome}/dotfiles/nostalgia";
    signal = "USR1";
  };
}
