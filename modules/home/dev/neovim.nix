{
  home-manager.users.whexy =
    { pkgs, lib, ... }:
    {
      # disable vim configs
      programs.vim = {
        enable = lib.mkForce false;
        defaultEditor = lib.mkForce false;
      };

      programs.neovim = {
        enable = true;
        defaultEditor = true;

        viAlias = true;
        vimAlias = true;
      };

      xdg.configFile."nvim" = {
        source = ../../../nvim;
        recursive = true;
      };
    };
}
