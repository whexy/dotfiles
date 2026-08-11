# Homebrew group: the Homebrew package manager machinery on macOS.
# Individual casks are gated by the functionality options of the semantic
# feature groups (browser, security, streaming, desktop).
{ lib, ... }:
{
  options.dotfiles.homebrew = {
    enable = lib.mkEnableOption "Homebrew (macOS)";
  };
}
