# Rclone FUSE mount for Backblaze B2
# Mounts the wenxuan-private bucket to ~/b2
# Linux-only (systemd user service)
{
  config,
  darwin ? false,
  lib,
  ...
}:
lib.mkIf (!darwin) {
  programs.rclone = {
    enable = true;
    remotes.b2 = {
      config = {
        type = "b2";
      };
      secrets = {
        account = config.age.secrets.b2-account.path;
        key = config.age.secrets.b2-key.path;
      };
      mounts.wenxuan-private = {
        enable = true;
        mountPoint = "${config.home.homeDirectory}/b2";
      };
    };
  };

  # The HM rclone module hardcodes PATH=/run/wrappers/bin (NixOS-specific).
  # On non-NixOS hosts, fusermount3 lives in /usr/bin, so we override the PATH.
  systemd.user.services."rclone-mount:wenxuan-private@b2".Service.Environment = lib.mkForce [
    "PATH=/run/wrappers/bin:/usr/bin:/usr/sbin"
  ];

  age.secrets = {
    b2-account.file = ../../secrets/b2-account.age;
    b2-key.file = ../../secrets/b2-key.age;
  };
}
