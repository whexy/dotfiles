# Btop configuration
{ ... }:
{
  programs.btop = {
    enable = true;
    settings = {
      theme_background = false;
      vim_keys = true;
      proc_filter_kernel = true; # hide kworkers
    };
  };
}
