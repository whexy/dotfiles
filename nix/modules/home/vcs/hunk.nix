# Hunks - terminal diff tool
# Note: inputs.hunk.homeManagerModules.default is imported by ./default.nix
# (this file is gated on dotfiles.dev.enable and cannot declare imports).
{
  config,
  lib,
  ...
}:
let
  cfg = config.dotfiles.vcs;
in
{
  config = lib.mkIf cfg.hunk.enable {
    programs.hunk = {
      enable = true;
      enableGitIntegration = true; # Optional: set hunk as default git pager
      settings = {
        theme = "graphite";
        mode = "split";
        line_numbers = true;
        tab_width = 4;
      };
    };
  };
}
