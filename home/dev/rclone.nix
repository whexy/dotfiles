# Rclone remote mounts
# - NAS WebDAV:       NAS storage → ~/mnt/nas
# - B2 + Crypt:       Backblaze B2 encrypted private storage → ~/mnt/b2private
#
# Linux:  systemd user services via HM rclone module (FUSE)
# macOS:  launchd agents with rclone nfsmount (built-in NFS server)
#         Secrets are injected into rclone.conf via `rclone config update`
#         during `darwin-rebuild switch` (HM activation script).
#         The config persists across reboots at ~/.config/rclone/rclone.conf.
{
  config,
  darwin ? false,
  lib,
  pkgs,
  ...
}:
let
  homeDir = config.home.homeDirectory;
  rcloneBin = lib.getExe config.programs.rclone.package;

  # ── Remote definitions (shared across platforms) ─────────────────────
  remoteConfigs = {
    nas = {
      type = "webdav";
      url = "https://nas-storage.shiwx.org/";
      vendor = "other";
      user = "whexy";
    };
    b2private-raw = {
      type = "b2";
    };
    b2private = {
      type = "crypt";
      remote = "b2private-raw:wenxuan-private";
      filename_encryption = "standard";
      directory_name_encryption = "true";
    };
  };

  remoteSecrets = {
    nas = {
      pass = config.age.secrets.nas-webdav-pass.path;
    };
    b2private-raw = {
      account = config.age.secrets.b2-account.path;
      key = config.age.secrets.b2-key.path;
    };
    b2private = {
      password = config.age.secrets.b2-crypt-password.path;
    };
  };

  mounts = {
    nas = "${homeDir}/mnt/nas";
    b2private = "${homeDir}/mnt/b2private";
  };

  # ── macOS: config-generation script ──────────────────────────────────
  # Runs during `darwin-rebuild switch` as a HM activation script (after
  # agenix decrypts secrets). Writes a base rclone.conf with static keys,
  # then injects secrets via `rclone config update` which handles password
  # obscuring automatically (same approach as the HM rclone module on Linux).
  rcloneConfigScript = pkgs.writeShellScript "rclone-config-gen" ''
    set -euo pipefail
    export PATH="${lib.makeBinPath [ config.programs.rclone.package ]}:$PATH"
    conf="${homeDir}/.config/rclone/rclone.conf"
    mkdir -p "$(dirname "$conf")"

    cat > "$conf" <<'CONF'
[nas]
type = webdav
url = https://nas-storage.shiwx.org/
vendor = other
user = whexy

[b2private-raw]
type = b2

[b2private]
type = crypt
remote = b2private-raw:wenxuan-private
filename_encryption = standard
directory_name_encryption = true
CONF
    chmod 600 "$conf"

    rclone config update nas pass "$(cat "${config.age.secrets.nas-webdav-pass.path}")"
    rclone config update b2private-raw account "$(cat "${config.age.secrets.b2-account.path}")"
    rclone config update b2private-raw key "$(cat "${config.age.secrets.b2-key.path}")"
    rclone config update b2private password "$(cat "${config.age.secrets.b2-crypt-password.path}")"
  '';

  # ── macOS: mount script ─────────────────────────────────────────────
  mkMountScript =
    remoteName: mountPoint:
    pkgs.writeShellScript "rclone-mount-${remoteName}" ''
      set -euo pipefail
      mkdir -p "${mountPoint}"
      exec ${rcloneBin} nfsmount \
        --vfs-cache-mode full \
        --cache-dir "${homeDir}/Library/Caches/rclone" \
        "${remoteName}:/" "${mountPoint}"
    '';

in
lib.mkMerge [
  # ── Common ────────────────────────────────────────────────────────
  {
    programs.rclone.enable = true;
  }

  # ── Linux: HM rclone module handles systemd services ──────────────
  (lib.mkIf (!darwin) {
    programs.rclone = {
      remotes.nas = {
        config = remoteConfigs.nas;
        secrets = remoteSecrets.nas;
        mounts."/" = {
          enable = true;
          mountPoint = mounts.nas;
        };
      };

      remotes.b2private-raw = {
        config = remoteConfigs.b2private-raw;
        secrets = remoteSecrets.b2private-raw;
      };

      remotes.b2private = {
        config = remoteConfigs.b2private;
        secrets = remoteSecrets.b2private;
        mounts."/" = {
          enable = true;
          mountPoint = mounts.b2private;
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
  })

  # ── macOS: activation + launchd agents with NFS mounts ────────────
  (lib.mkIf darwin {
    # Generate rclone.conf with secrets during activation (after agenix).
    # The config persists across reboots so mount agents can use it.
    home.activation.rclone-config = lib.hm.dag.entryAfter [ "agenix" ] ''
      run ${rcloneConfigScript}
    '';

    # NAS WebDAV mount
    launchd.agents.rclone-mount-nas = {
      enable = true;
      config = {
        ProgramArguments = [ "${mkMountScript "nas" mounts.nas}" ];
        RunAtLoad = true;
        KeepAlive = {
          Crashed = true;
          SuccessfulExit = false;
        };
        StandardOutPath = "${homeDir}/Library/Logs/rclone-mount-nas.log";
        StandardErrorPath = "${homeDir}/Library/Logs/rclone-mount-nas.log";
        ProcessType = "Background";
      };
    };

    # B2 encrypted private storage mount
    launchd.agents.rclone-mount-b2private = {
      enable = true;
      config = {
        ProgramArguments = [ "${mkMountScript "b2private" mounts.b2private}" ];
        RunAtLoad = true;
        KeepAlive = {
          Crashed = true;
          SuccessfulExit = false;
        };
        StandardOutPath = "${homeDir}/Library/Logs/rclone-mount-b2private.log";
        StandardErrorPath = "${homeDir}/Library/Logs/rclone-mount-b2private.log";
        ProcessType = "Background";
      };
    };
  })
]
