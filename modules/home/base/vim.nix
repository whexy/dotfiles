{
  home-manager.users.whexy =
    { pkgs, ... }:
    {
      programs.vim = {
        enable = true;
        defaultEditor = true;
      };
    };
}
