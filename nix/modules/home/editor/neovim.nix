# Minimal Neovim configuration for base capability
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.dotfiles.editor;
in
{
  config = lib.mkIf cfg.neovim.enable {
    programs.neovim = lib.mkDefault {
      enable = true;
      package = pkgs.unstable.neovim-unwrapped;
      # We set EDITOR/VISUAL ourselves (below) to the absolute store path of the
      # wrapped nvim, so disable the module's hardcoded `EDITOR = "nvim"`.
      defaultEditor = false;
      viAlias = true;
      vimAlias = true;
    };

    # Point editor env vars at the absolute path of the home-manager nvim.
    # A bare "nvim" would be resolved against PATH, which under `sudo -e`
    # (sudoedit) uses root's secure_path and picks the distro nvim instead of
    # this configured one. SUDO_EDITOR is honored first by sudoedit (and by the
    # oh-my-zsh sudo plugin's editor matcher).
    home.sessionVariables =
      let
        nvim = lib.getExe config.programs.neovim.finalPackage;
      in
      {
        EDITOR = nvim;
        VISUAL = nvim;
        SUDO_EDITOR = nvim;
      };

    xdg.configFile."nvim" = lib.mkDefault {
      source = ./nvim-base;
      recursive = true;
    };
  };
}
