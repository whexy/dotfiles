args@{
  lib,
  pkgs,
  ...
}:
let
  osConfig = args.osConfig or { };
  enabled = osConfig.dotfiles.terminal.cmux.enable or false;
  macbookScreen = osConfig.dotfiles.hardware.display.macbookScreen or false;
in
{
  config = lib.mkIf (enabled && pkgs.stdenv.hostPlatform.isDarwin) {
    xdg.configFile."cmux/cmux.json".source = (pkgs.formats.json { }).generate "cmux.json" {
      "$schema" = "https://raw.githubusercontent.com/manaflow-ai/cmux/main/web/data/cmux.schema.json";
      schemaVersion = 1;
      app = {
        openSupportedFilesInCmux = false;
        openMarkdownInCmuxViewer = false;
        preferredEditor = "";
      };
      fileExplorer.doubleClickAction = "defaultEditor";
      browser = {
        openTerminalLinksInCmuxBrowser = false;
        interceptTerminalOpenCommandInCmuxBrowser = false;
        hostsToOpenInEmbeddedBrowser = [ ];
      };
      sidebar = {
        openPullRequestLinksInCmuxBrowser = false;
        openPortLinksInCmuxBrowser = false;
      };
    };

    # cmux loads this after the shared Ghostty config, before recursive includes.
    # Clear those includes so Ghostty's mutable theme/font toggles cannot override it.
    home.file."Library/Application Support/com.cmuxterm.app/config.ghostty".text = ''
      config-file =
      theme = Gruvbox Dark
      font-family = FiraCode Nerd Font
      font-size = ${if macbookScreen then "16" else "14"}
      background-opacity = 0.90
      background-blur = true
      keybind = cmd+shift+t=unbind
    '';
  };
}
