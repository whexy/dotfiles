# Rclone remote mounts
# - NAS WebDAV:       NAS storage → ~/mnt/nas
# - B2 + Crypt:       Backblaze B2 encrypted private storage → ~/mnt/b2private
#
# Linux:  systemd user services via HM rclone module (FUSE)
# macOS:  launchd agents with rclone nfsmount (built-in NFS server)
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

  # ── macOS: config-generation script ─────────────────────────────────
  # Generates ~/.config/rclone/rclone.conf with secrets injected at
  # runtime via `rclone config update` (which handles password obscuring
  # for crypt remotes automatically — same approach as the HM module on Linux).
  rcloneConfigScript = pkgs.writeShellScript "rclone-config-gen" ''
    set -euo pipefail
    export PATH="${lib.makeBinPath [ config.programs.rclone.package ]}:$PATH"
    conf_dir="${homeDir}/.config/rclone"
    mkdir -p "$conf_dir"

    # 1. Write base config with static keys (no secrets)
    cat > "$conf_dir/rclone.conf" <<'CONF'
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
    # strip leading whitespace from heredoc
    sed -i "" 's/^    //' "$conf_dir/rclone.conf"

    chmod 600 "$conf_dir/rclone.conf"

    # 2. Inject secrets via rclone config update (handles obscuring)
    inject() {
      local remote="$1" key="$2" file="$3"
      if [ -f "$file" ]; then
        rclone config update "$remote" "$key" "$(cat "$file")"
      else
        echo "WARNING: secret file not found: $file" >&2
      fi
    }

    inject nas pass "${config.age.secrets.nas-webdav-pass.path}"
    inject b2private-raw account "${config.age.secrets.b2-account.path}"
    inject b2private-raw key "${config.age.secrets.b2-key.path}"
    inject b2private password "${config.age.secrets.b2-crypt-password.path}"
  '';

  # ── macOS: mount script wrapper ─────────────────────────────────────
  # Waits for rclone.conf to exist, then mounts via NFS (rclone nfsmount).
  mkMountScript =
    remoteName: mountPoint:
    pkgs.writeShellScript "rclone-mount-${remoteName}" ''
      set -euo pipefail
      conf="${homeDir}/.config/rclone/rclone.conf"

      # Wait for config to be generated (up to 30s)
      for i in $(seq 1 30); do
        [ -f "$conf" ] && break
        sleep 1
      done
      if [ ! -f "$conf" ]; then
        echo "rclone.conf not found after 30s, aborting" >&2
        exit 1
      fi

      mkdir -p "${mountPoint}"
      exec ${rcloneBin} nfsmount \
        --vfs-cache-mode full \
        --cache-dir "${homeDir}/Library/Caches/rclone" \
        "${remoteName}:/" "${mountPoint}"
    '';

in
lib.mkMerge [
  {
    programs.rclone.enable = true;
  }

  # Linux: HM rclone module handles systemd services
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

  # macOS: custom launchd agents with NFS-mode mounts
  (lib.mkIf darwin {
    # Config generation agent — runs at login, injects secrets into rclone.conf
    launchd.agents.rclone-config = {
      enable = true;
      config = {
        ProgramArguments = [ "${rcloneConfigScript}" ];
        RunAtLoad = true;
        # Re-run if it crashes (e.g. secrets not yet available)
        KeepAlive = {
          SuccessfulExit = false;
        };
        StandardOutPath = "${homeDir}/Library/Logs/rclone-config.log";
        StandardErrorPath = "${homeDir}/Library/Logs/rclone-config.log";
        ProcessType = "Background";
      };
    };

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
