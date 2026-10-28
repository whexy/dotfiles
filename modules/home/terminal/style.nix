# Font and color themes shared by the terminal emulators, so that Rex looks
# like Ghostty. Theme names are files in Ghostty's themes directory.
{
  font = "FiraCode Nerd Font";
  fontSize = macbookScreen: if macbookScreen then 16 else 14;
  darkTheme = "Gruvbox Dark";
  # lightTheme = "Catppuccin Latte";
  lightTheme = "Gruvbox Light";
}
