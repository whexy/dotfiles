# Btop configuration
{
  config,
  lib,
  ...
}:
let
  cfg = config.dotfiles.monitors;
in
{
  config = lib.mkIf cfg.btop.enable {
    programs.btop = {
      enable = true;
      settings = {
        theme_background = false;
        vim_keys = true;
        proc_filter_kernel = true; # hide kworkers
      };
    };
  };
}
