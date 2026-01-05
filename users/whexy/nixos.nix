{ pkgs, username, ... }:
{
  # User configuration
  users.mutableUsers = false;
  users.users.${username} = {
    isNormalUser = true;
    description = username;
    home = "/home/${username}";
    shell = pkgs.zsh;
    extraGroups = [
      "wheel"
      "networkmanager"
      "docker"
    ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMdMvHl7VPzajwBjWw+pqcLatA42yWtQKiEPj/9VqI9i"
    ];
  };
}
