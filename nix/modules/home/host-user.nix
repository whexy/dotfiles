# Home Manager entry point for users integrated into NixOS or Darwin.
# Caps arrive as preset names, not as config options. Home modules read host
# feature options directly from osConfig.dotfiles.* when needed.
{
  inputs,
  dotfilesCaps,
  ...
}:
{
  imports = [ inputs.self.homeModules.all ] ++ inputs.self.lib.homeCapsModules dotfilesCaps;
}
