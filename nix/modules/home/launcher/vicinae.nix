# Vicinae: native command palette (app search, clipboard history, emoji,
# calculator, window switcher) replacing the fuzzel launcher and the
# cliphist clipboard picker.
#
# The daemon holds the search index and the clipboard history, so it runs as a
# session service; the niri binds in wm/niri.nix only send IPC commands to it.
args@{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  osConfig = args.osConfig or null;
  cfg = config.dotfiles.launcher;
  isDarwin = osConfig != null && lib.hasSuffix "-darwin" osConfig.dotfiles.host.system;
  inputServerEnabled = osConfig.dotfiles.launcher.inputServer.enable or false;
  storeExtensions = inputs.vicinae-extensions.packages.${pkgs.stdenv.hostPlatform.system};
in
{
  config = lib.mkIf (cfg.vicinae.enable && !isDarwin) {
    programs.vicinae = {
      enable = true;
      systemd = {
        enable = true;
        target = "graphical-session.target";
      };

      settings = {
        # Theme ids are the file stems of the .toml themes bundled in the
        # package's share/vicinae/themes, found through XDG_DATA_DIRS.
        # Gruvbox matches the waybar and mako palettes.
        theme = {
          dark.name = "gruvbox-dark";
          light.name = "gruvbox-light";
        };

        # Root search only lists apps, commands and clipboard entries. The
        # file index is still reachable through the dedicated file search
        # command, without paying for an index query on every keystroke.
        search_files_in_root = false;
      };

      extensions = [
        storeExtensions.niri
        storeExtensions.nix
      ];
    };

    # The daemon otherwise looks for the helper next to its own binary, where
    # it has no capabilities. Point it at the setcap wrapper that the system
    # launcher group installs.
    systemd.user.services.vicinae.Service.Environment = lib.mkIf inputServerEnabled [
      "VICINAE_INPUT_SERVER_BIN=/run/wrappers/bin/vicinae-input-server"
    ];
  };
}
