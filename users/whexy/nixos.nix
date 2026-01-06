{ pkgs, username, ... }:
{
  # User configuration
  users.mutableUsers = false;
  users.users.${username} = {
    isNormalUser = true;
    description = username;
    home = "/home/${username}";
    hashedPassword = "$y$j9T$hS1I2iWez3k8r1EH6ZIKG.$rATY9sBbSiudRf7T5MOEWlLraL6WFY5K6uB0MZj3Q.4";
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
