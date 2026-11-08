# Neovide GUI configuration (mirrors Ghostty's look & feel)
args@{
  config,
  lib,
  pkgs,
  ...
}:
let
  osConfig = args.osConfig or null;
  cfg = config.dotfiles.editor;
  style = import ../terminal/style.nix;
in
{
  config = lib.mkIf cfg.neovide.enable (
    let
      macbookScreen = osConfig.dotfiles.hardware.display.macbookScreen or false;
    in
    {
      programs.neovide = {
        enable = true;
        settings = {
          font = {
            normal = [ style.font ];
            # Neovide's font size is a float.
            size = 0.0 + style.fontSize macbookScreen;
          };
          transparency = style.opacity;
        }
        # Same as Ghostty's background-blur; Neovide only supports blur on macOS
        // lib.optionalAttrs pkgs.stdenv.hostPlatform.isDarwin { background-blur-radius = 20; };
      };
    }
  );
}
