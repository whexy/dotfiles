# Rclone remote mounts — single declarative definition for all platforms.
#
#   nas:    WebDAV  → ~/mnt/nas
#   b2:     B2 + crypt → ~/mnt/b2  (b2-raw is the underlying backend)
#
# Linux:  systemd user services (FUSE via `rclone mount`).
# macOS:  launchd agents (native NFS via `rclone nfsmount`, no macFUSE).
#
# Both platforms are driven by the same `programs.rclone.remotes` data,
# wired up by ../modules/programs/rclone.nix.
{ config, lib, ... }:
let
  homeDir = config.home.homeDirectory;
in
{
  programs.rclone = {
    enable = true;

    remotes = {
      nas = {
        config = {
          type = "webdav";
          url = "https://nas-storage.shiwx.org/";
          vendor = "other";
          user = "whexy";
        };
        secrets = {
          pass = config.age.secrets.nas-webdav-pass.path;
        };
        mounts."/" = {
          enable = true;
          mountPoint = "${homeDir}/mnt/nas";
          options = {
            disable-http2 = true;
            timeout = "30s";
            contimeout = "10s";
            low-level-retries = 3;
            retries = 3;
            dir-cache-time = "5m";
            poll-interval = "1m";
            attr-timeout = "10s";
            no-modtime = true;
          };
        };
      };

      b2-raw = {
        config.type = "b2";
        secrets = {
          account = config.age.secrets.b2-account.path;
          key = config.age.secrets.b2-key.path;
        };
      };

      b2 = {
        config = {
          type = "crypt";
          remote = "b2-raw:wenxuan-private";
          filename_encryption = "standard";
          directory_name_encryption = "true";
        };
        secrets = {
          password = config.age.secrets.b2-crypt-password.path;
        };
        mounts."/" = {
          enable = true;
          mountPoint = "${homeDir}/mnt/b2";
        };
      };
    };
  };

  # The HM rclone module hardcodes PATH=/run/wrappers/bin (NixOS-specific).
  # On non-NixOS Linux hosts, fusermount3 lives in /usr/bin, so we extend it.
  # This block targets `systemd.user.services` which is silently ignored on
  # Darwin (systemd.user.enable defaults to false there).
  systemd.user.services."rclone-mount:.@nas".Service.Environment = lib.mkForce [
    "PATH=/run/wrappers/bin:/usr/bin:/usr/sbin"
  ];
  systemd.user.services."rclone-mount:.@b2".Service.Environment = lib.mkForce [
    "PATH=/run/wrappers/bin:/usr/bin:/usr/sbin"
  ];
}
