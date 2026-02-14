# Rclone FUSE mounts
# - Backblaze B2: wenxuan-private bucket → ~/b2
# - WebDAV: alist NAS → ~/nas
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
    remotes.nas = {
      config = {
        type = "webdav";
        url = "https://alist-whexyhomenas.shiwx.org/dav";
        vendor = "other";
      };
      config.user = "whexy";
      secrets = {
        pass = config.age.secrets.nas-webdav-pass.path;
      };
      mounts."/" = {
        enable = true;
        mountPoint = "${config.home.homeDirectory}/nas";
      };
    };
  };

  # The HM rclone module hardcodes PATH=/run/wrappers/bin (NixOS-specific).
  # On non-NixOS hosts, fusermount3 lives in /usr/bin, so we override the PATH.
  systemd.user.services."rclone-mount:wenxuan-private@b2".Service.Environment = lib.mkForce [
    "PATH=/run/wrappers/bin:/usr/bin:/usr/sbin"
  ];
  systemd.user.services."rclone-mount:.@nas".Service.Environment = lib.mkForce [
    "PATH=/run/wrappers/bin:/usr/bin:/usr/sbin"
  ];

  age.secrets = {
    b2-account.file = ../../secrets/b2-account.age;
    b2-key.file = ../../secrets/b2-key.age;
    nas-webdav-pass.file = ../../secrets/nas-webdav-pass.age;
  };
}
