# Shell configuration
{
  home-manager.users.whexy =
    { pkgs, ... }:
    {
      programs.zsh = {
        enable = true;
        enableCompletion = true;

        history = {
          save = 10000;
          size = 10000;
          share = true;
        };
      };
    };
}
