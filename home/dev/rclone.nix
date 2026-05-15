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
#
# ── Cloudflare Access on the NAS ─────────────────────────────────────
# The NAS WebDAV endpoint is fronted by a Cloudflare Tunnel and gated by a
# Cloudflare Access "Service Auth" policy. Requests must carry two HTTP
# headers:
#
#     CF-Access-Client-Id:     <from secrets/cf-access-nas-client-id.age>
#     CF-Access-Client-Secret: <from secrets/cf-access-nas-client-secret.age>
#
# rclone reads `RCLONE_HEADER` (comma-separated `Header: Value` pairs) from
# the environment, but neither systemd nor launchd can interpolate
# environment values from on-disk files. So the per-mount unit's command is
# wrapped in a tiny shell script (`cfAccessWrapper`) that:
#
#   1. reads both secret files at runtime, and
#   2. exports `RCLONE_HEADER`, then `exec`s rclone with the original args.
#
# This is symmetrical to how `programs.rclone.remotes.*.secrets` already
# handles the WebDAV password (via `rclone config update`), except headers
# aren't a config field — they're a CLI/env-time concern.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  homeDir = config.home.homeDirectory;

  cfIdPath = config.age.secrets.cf-access-nas-client-id.path;
  cfSecretPath = config.age.secrets.cf-access-nas-client-secret.path;

  # Wrapper: reads CF Access secrets from disk, sets RCLONE_HEADER, exec's
  # whatever command (with args) it was given. Usage:
  #   cfAccessWrapper /path/to/rclone mount ...
  cfAccessWrapper = pkgs.writeShellScript "rclone-nas-cf-access-wrapper" ''
    set -euo pipefail

    if [[ ! -r "${cfIdPath}" ]]; then
      echo "rclone-nas-cf-access-wrapper: missing ${cfIdPath}" >&2
      exit 1
    fi
    if [[ ! -r "${cfSecretPath}" ]]; then
      echo "rclone-nas-cf-access-wrapper: missing ${cfSecretPath}" >&2
      exit 1
    fi

    # Use bash's `$(<file)` builtin instead of `cat` to avoid depending on
    # PATH at runtime — the systemd unit's Environment override below
    # sanitizes PATH and `cat` isn't available in `/usr/bin` on NixOS.
    cf_id=$(<"${cfIdPath}")
    cf_secret=$(<"${cfSecretPath}")

    # rclone's `RCLONE_HEADER` env var doesn't reliably CSV-split into
    # multiple header entries (it ends up either as one mashed string or
    # with literal quote chars in the header name, depending on the form).
    # Inject `--header` twice as CLI args instead — this works
    # unambiguously and is position-independent.
    exec "$@" \
      --header "CF-Access-Client-Id: $cf_id" \
      --header "CF-Access-Client-Secret: $cf_secret"
  '';

  rcloneBin = lib.getExe config.programs.rclone.package;

  nasMountPoint = "${homeDir}/mnt/nas";

  # Pull the post-`apply` mount options straight from the module so we
  # inherit the shared module's defaults (vfs-cache-mode, cache-dir, etc.)
  # without duplicating them here.
  nasMountOptions = config.programs.rclone.remotes.nas.mounts."/".options;

  # Darwin cache-dir rewrite — mirrors the logic in the shared rclone
  # module so we can construct an equivalent `nfsmount` command line.
  darwinCacheDir = "${homeDir}/Library/Caches/rclone";
  nasMountOptionsDarwin = lib.mapAttrs (
    k: v: if k == "cache-dir" && v == "%C/rclone" then darwinCacheDir else v
  ) nasMountOptions;

  # Reconstruct rclone command lines locally. The shared module renders
  # `ExecStart` as a single string on Linux and a single-element
  # `ProgramArguments` script on Darwin; we override both to route through
  # `cfAccessWrapper`.
  nasLinuxExecStart = lib.concatStringsSep " " [
    "${cfAccessWrapper}"
    rcloneBin
    "mount"
    (lib.cli.toGNUCommandLineShell { } nasMountOptions)
    "nas:/"
    nasMountPoint
  ];

  # Darwin: the existing per-mount script does `mkdir -p` + `exec rclone
  # nfsmount …`. We replicate it here, but invoke rclone through the
  # wrapper so RCLONE_HEADER is set.
  nasDarwinScript = pkgs.writeShellScript "rclone-mount-nas" ''
    set -euo pipefail
    mkdir -p "${nasMountPoint}"
    exec ${cfAccessWrapper} ${rcloneBin} nfsmount \
      ${lib.cli.toGNUCommandLineShell { } nasMountOptionsDarwin} \
      "nas:/" "${nasMountPoint}"
  '';
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
          mountPoint = nasMountPoint;
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

  # ── Linux (systemd user) overrides ───────────────────────────────────
  # - PATH: HM rclone module hardcodes /run/wrappers/bin (NixOS-specific).
  #   On non-NixOS Linux hosts, fusermount3 lives in /usr/bin, so extend it.
  # - nas ExecStart: route through cfAccessWrapper so RCLONE_HEADER is set
  #   before rclone runs. The shared module's ExecStartPre (`mkdir -p`)
  #   stays untouched.
  # Both blocks are silently ignored on Darwin (systemd.user is disabled).
  systemd.user.services."rclone-mount:.@nas".Service = {
    Environment = lib.mkForce [
      "PATH=/run/wrappers/bin:/usr/bin:/usr/sbin"
    ];
    ExecStart = lib.mkForce nasLinuxExecStart;
  };
  systemd.user.services."rclone-mount:.@b2".Service.Environment = lib.mkForce [
    "PATH=/run/wrappers/bin:/usr/bin:/usr/sbin"
  ];

  # ── Darwin (launchd) override ────────────────────────────────────────
  # Replace the shared module's nas mount script with one that injects
  # RCLONE_HEADER via cfAccessWrapper. No-op on Linux (launchd.agents is
  # not evaluated there).
  launchd.agents."rclone-mount:.@nas".config.ProgramArguments = lib.mkForce [
    "${nasDarwinScript}"
  ];
}
