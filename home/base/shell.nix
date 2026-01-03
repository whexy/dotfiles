# Shell configuration
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

  programs.ssh = {
    enable = true;
    matchBlocks = {
      "*" = {
        extraOptions = {
          AddKeysToAgent = "yes";
        };
      };
    };
  };

  # SSH authorized keys for remote access
  home.file.".ssh/authorized_keys".text = ''
    ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMdMvHl7VPzajwBjWw+pqcLatA42yWtQKiEPj/9VqI9i
  '';
}
