# Fonts NixOS configuration: font packages and fontconfig defaults,
# including CJK (Chinese) fallback rules.
{
  config,
  pkgs,
  lib,
  perSystem,
  ...
}:
let
  cfg = config.dotfiles.fonts;
in
{
  config = lib.mkIf cfg.enable {
    fonts = {
      packages = [
        perSystem.self.perfect-dos-vga-437-nerd-font
        pkgs.nerd-fonts.fira-code
        pkgs.nerd-fonts.jetbrains-mono
        pkgs.noto-fonts-cjk-sans
        pkgs.noto-fonts-cjk-serif
      ];

      fontconfig.defaultFonts = {
        monospace = [ "FiraCode Nerd Font" ];
      };

      fontconfig.localConf = ''
        <?xml version="1.0"?>
        <!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
        <fontconfig>
          <!-- Default sans-serif font for Chinese (Simplified) -->
          <match>
            <test name="lang" compare="contains">
              <string>zh</string>
            </test>
            <test name="family">
              <string>sans-serif</string>
            </test>
            <edit name="family" mode="prepend">
              <string>Noto Sans CJK SC</string>
            </edit>
          </match>

          <!-- Default serif font for Chinese (Simplified) -->
          <match>
            <test name="lang" compare="contains">
              <string>zh</string>
            </test>
            <test name="family">
              <string>serif</string>
            </test>
            <edit name="family" mode="prepend">
              <string>Noto Serif CJK SC</string>
            </edit>
          </match>

          <!-- Default monospace font for Chinese (Simplified) -->
          <match>
            <test name="lang" compare="contains">
              <string>zh</string>
            </test>
            <test name="family">
              <string>monospace</string>
            </test>
            <edit name="family" mode="prepend">
              <string>Noto Sans CJK SC</string>
            </edit>
          </match>
        </fontconfig>
      '';
    };
  };
}
