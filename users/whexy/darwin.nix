{ pkgs, username, ... }:
{
  system.primaryUser = username;

  # work-around for chsh on macOS
  users.knownUsers = [ username ];

  # User configuration
  users.users.${username} = {
    description = username;
    uid = 501;
    home = "/Users/${username}";
    shell = pkgs.fish;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMdMvHl7VPzajwBjWw+pqcLatA42yWtQKiEPj/9VqI9i"
    ];
  };

  nix.settings.trusted-users = [
    "root"
    username
  ];
}
