{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.dotfiles.user;
  username = config.dotfiles.host.username;
in
{
  config = lib.mkIf cfg.enable {
    system.primaryUser = username;

    # Work around chsh on macOS.
    users.knownUsers = [ username ];
    users.users.${username} = {
      description = username;
      uid = 501;
      home = "/Users/${username}";
      shell = if config.dotfiles.shell.default == "nushell" then pkgs.nushell else pkgs.zsh;
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMdMvHl7VPzajwBjWw+pqcLatA42yWtQKiEPj/9VqI9i"
      ];
    };

    nix.settings.trusted-users = [
      "root"
      username
    ];
  };
}
