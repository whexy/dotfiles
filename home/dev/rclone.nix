# Rclone FUSE mounts
# - B2 + Crypt: Backblaze B2 encrypted private storage → ~/mnt/b2private
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

    # -- NAS WebDAV (currently not working) --
    remotes.nas = {
      config = {
        type = "webdav";
        url = "https://nas-storage.shiwx.org/";
        vendor = "other";
      };
      config.user = "whexy";
      secrets = {
        pass = config.age.secrets.nas-webdav-pass.path;
      };
      mounts."/" = {
        enable = true;
        mountPoint = "${config.home.homeDirectory}/mnt/nas";
      };
    };

    # -- Backblaze B2 (raw, used as backend for the crypt layer) --
    remotes.b2private-raw = {
      config = {
        type = "b2";
      };
      secrets = {
        account = config.age.secrets.b2-account.path;
        key = config.age.secrets.b2-key.path;
      };
    };

    # -- Crypt overlay on top of B2 --
    remotes.b2private = {
      config = {
        type = "crypt";
        remote = "b2private-raw:wenxuan-private";
        filename_encryption = "standard";
        directory_name_encryption = "true";
      };
      secrets = {
        password = config.age.secrets.b2-crypt-password.path;
      };
      mounts."/" = {
        enable = true;
        mountPoint = "${config.home.homeDirectory}/mnt/b2private";
      };
    };
  };

  # The HM rclone module hardcodes PATH=/run/wrappers/bin (NixOS-specific).
  # On non-NixOS hosts, fusermount3 lives in /usr/bin, so we override the PATH.
  systemd.user.services."rclone-mount:.@nas".Service.Environment = lib.mkForce [
    "PATH=/run/wrappers/bin:/usr/bin:/usr/sbin"
  ];

  systemd.user.services."rclone-mount:.@b2private".Service.Environment = lib.mkForce [
    "PATH=/run/wrappers/bin:/usr/bin:/usr/sbin"
  ];
}
