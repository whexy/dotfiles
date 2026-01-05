{ pkgs, username, ... }:
{
  # User configuration
  users.users.${username} = {
    description = username;
    home = "/Users/${username}";
    shell = pkgs.zsh;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMdMvHl7VPzajwBjWw+pqcLatA42yWtQKiEPj/9VqI9i"
    ];
  };
}
