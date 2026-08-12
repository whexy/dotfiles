# rclone service definitions: render rclone.conf, inject secrets, and mount
# remotes as systemd user services (Linux) or launchd agents (Darwin).
#
# Upstream HM only emits systemd user services, which means Darwin hosts get
# the rclone.conf option machinery but no service to actually install the
# config file nor mount the remotes. This file is gated by
# `dotfiles.rclone.enable` and reads the `programs.rclone.*` options that
# ./default.nix re-declares (and whose upstream module it disables). It only
# provides the service definitions:
#
#   - Linux:  identical behavior to upstream (systemd user services for
#             rclone-config and one mount unit per `remote.mounts` entry).
#
#   - Darwin: equivalent launchd agents:
#               * `rclone-config` — writes rclone.conf and injects secrets.
#               * `rclone-mount:<path>@<remote>` — runs `rclone nfsmount`
#                 (rclone's built-in NFS server, no macFUSE required).
#
# launchd has no `Requires=`/`After=` primitive, so ordering between
# secret provisioning (agenix, sops-nix, manual files, …) and the
# `rclone-config` agent is handled by:
#
#   * `RunAtLoad = true`            — first start at user login / rebuild.
#   * `KeepAlive.SuccessfulExit = false` — retry until config writes succeed.
#   * `WatchPaths = <secret files>` — re-fire whenever any secret changes,
#                                     so a rotated password is picked up
#                                     automatically without manual reload.
#
# The `WatchPaths` list is sourced from `cfg.remotes.*.secrets`, making this
# module agnostic to the specific secret provisioner.
#
# NOTE: The Linux branch is a near-verbatim fork of nix-community/home-manager
# `modules/programs/rclone.nix` (release-25.11), duplicated rather than
# imported so a single source-of-truth handles both platforms. Re-sync with
# upstream periodically.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.rclone;
  iniFormat = pkgs.formats.ini { };
  inherit (pkgs.stdenv.hostPlatform) isDarwin;
  inherit (pkgs.stdenv.hostPlatform) isLinux;
  replaceSlashes = builtins.replaceStrings [ "/" ] [ "." ];
  homeDir = config.home.homeDirectory;

  rcloneConfigPath = "${config.xdg.configHome}/rclone/rclone.conf";

  # ── Shared: base rclone.conf (no secrets) ────────────────────────────
  safeConfig = lib.pipe cfg.remotes [
    (lib.mapAttrs (_: v: v.config))
    (iniFormat.generate "rclone.conf@pre-secrets")
  ];

  # ── Shared: secret-injection shell snippets ──────────────────────────
  injectSecret =
    remote:
    lib.mapAttrsToList (secret: secretFile: ''
      if [[ ! -r "${secretFile}" ]]; then
        echo "Secret \"${secretFile}\" not found"
        cleanup
      fi

      if ! ${lib.getExe cfg.package} config update \
             ${remote.name} config_refresh_token=false \
             ${secret}="$(cat "${secretFile}")" \
             --non-interactive; then
        echo "Failed to inject secret \"${secretFile}\""
        cleanup
      fi
    '') (remote.value.secrets or { });

  injectAllSecrets = lib.concatMap injectSecret (lib.mapAttrsToList lib.nameValuePair cfg.remotes);

  # ── Shared: oneshot config-writer (used by both systemd + launchd) ───
  rcloneConfigApp = pkgs.writeShellApplication {
    name = "rclone-config";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      configPath="${rcloneConfigPath}"
      configName="$(basename "$configPath")"
      savedConfigPath="$(dirname "$configPath")"/."$configName".orig

      cleanup() {
        echo "Failed to render config."
        if [ -f "$savedConfigPath" ]; then
          cp -v "$savedConfigPath" "${rcloneConfigPath}"
        fi
        exit 1
      }

      trap cleanup SIGINT

      if [ -f "${rcloneConfigPath}" ]; then
        cp -v "${rcloneConfigPath}" "$savedConfigPath"
      fi

      install -v -D -m600 "${safeConfig}" "${rcloneConfigPath}"
      ${lib.concatLines injectAllSecrets}
    '';
  };

  # ── Darwin: rewrite the systemd %C specifier in cache-dir defaults ───
  # Upstream sets `cache-dir = "%C/rclone"` as a default; %C is a systemd
  # specifier (≈ $XDG_CACHE_HOME) that launchd doesn't expand. Translate it
  # to the canonical macOS cache location.
  darwinCacheDir = "${homeDir}/Library/Caches/rclone";
  rewriteDarwinCacheDir =
    opts: lib.mapAttrs (k: v: if k == "cache-dir" && v == "%C/rclone" then darwinCacheDir else v) opts;

  # ── Darwin: per-mount wrapper script ────────────────────────────────
  # Wraps `rclone nfsmount` in a small shell script so we can `mkdir -p`
  # the mount point first (analogous to the systemd ExecStartPre on Linux),
  # and so launchd's ProgramArguments stays simple.
  mkDarwinMountScript =
    remoteName: mountPath: mount:
    let
      opts = rewriteDarwinCacheDir mount.options;
      cliArgs = lib.cli.toCommandLineShellGNU { } opts;
    in
    pkgs.writeShellScript "rclone-mount-${remoteName}" ''
      set -euo pipefail
      mkdir -p "${mount.mountPoint}"
      exec ${lib.getExe cfg.package} nfsmount \
        ${cliArgs} \
        "${remoteName}:${mountPath}" "${mount.mountPoint}"
    '';

  # ── Darwin: secret file paths to watch ──────────────────────────────
  # All secret file paths across every remote. Whenever any of these
  # changes on disk, launchd re-fires `rclone-config`, which re-injects
  # secrets via `rclone config update`. This is the launchd-native way
  # to chain after a secret provisioner (sops-nix, manually-placed files,
  # ...) without any provisioner-specific knowledge in this module.
  #
  # We filter to paths that are eval-time absolute strings. Some
  # provisioners (notably agenix on Darwin) use runtime shell expansions
  # like `$(getconf DARWIN_USER_TEMP_DIR)/agenix/<name>` for their secret
  # paths, which launchd cannot expand for `WatchPaths` (it requires real
  # absolute paths). For those cases `WatchPaths` is omitted and the
  # `KeepAlive.SuccessfulExit = false` retry covers re-injection after
  # the agenix launchd agent finishes decrypting.
  allSecretPaths = lib.unique (
    lib.filter (p: lib.isString p && lib.hasPrefix "/" p) (
      lib.flatten (lib.mapAttrsToList (_: remote: lib.attrValues remote.secrets) cfg.remotes)
    )
  );

  # Filtered list of remotes that have at least one mount.
  remotesWithMounts = lib.filter (rem: rem.value ? mounts) (lib.attrsToList cfg.remotes);

in
{
  config = lib.mkIf config.dotfiles.rclone.enable (
    lib.mkMerge [
      { home.packages = [ cfg.package ]; }

      # ── Linux: systemd user services (identical to upstream HM) ───────
      (lib.mkIf isLinux {
        systemd.user.services = lib.mkMerge [
          (lib.mkIf (cfg.remotes != { }) {
            rclone-config = {
              Unit = lib.mkMerge [
                { Description = "Install rclone configuration to ${rcloneConfigPath}"; }
                (lib.optionalAttrs (cfg.requiresUnit != null) {
                  Requires = [ cfg.requiresUnit ];
                  After = [ cfg.requiresUnit ];
                })
              ];

              Service = {
                Type = "oneshot";
                ExecStart = lib.getExe rcloneConfigApp;
                Restart = "on-abnormal";
              };

              Install.WantedBy = [ "default.target" ];
            };
          })

          (lib.listToAttrs (
            lib.concatMap (
              { name, value }:
              let
                remoteName = name;
                remote = value;
              in
              lib.concatMap (
                { name, value }:
                let
                  mountPath = name;
                  mount = value;
                in
                [
                  (lib.nameValuePair "rclone-mount:${replaceSlashes mountPath}@${remoteName}" {
                    Unit = {
                      Description = "Rclone FUSE daemon for ${remoteName}:${mountPath}";
                      # Mount units must not start until rclone-config.service
                      # has finished writing rclone.conf AND injecting all
                      # secrets via `rclone config update`. Without this
                      # ordering, the mount can win the race against the
                      # config service and start with a stub config that
                      # lacks credential fields (e.g. WebDAV `pass`). For
                      # remotes where a missing secret isn't fatal (rclone
                      # happily mounts an unauthenticated WebDAV remote),
                      # this silently produces a "successful" mount that
                      # 401s on every request. `Requires=` also chains in
                      # `agenix.service` / `sops-nix.service` transitively
                      # via rclone-config's own dependency, so any
                      # per-mount wrappers that read secret files directly
                      # (e.g. for CF Access headers) are also safe.
                      After = [ "rclone-config.service" ];
                      Requires = [ "rclone-config.service" ];
                    };

                    Service = {
                      Type = "notify";
                      Environment = [
                        "PATH=/run/wrappers/bin"
                      ]
                      ++ lib.optional (mount.logLevel != null) "RCLONE_LOG_LEVEL=${mount.logLevel}";

                      ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p ${mount.mountPoint}";
                      ExecStart = lib.concatStringsSep " " [
                        (lib.getExe cfg.package)
                        "mount"
                        (lib.cli.toCommandLineShellGNU { } mount.options)
                        "${remoteName}:${mountPath}"
                        "${mount.mountPoint}"
                      ];
                      Restart = "on-failure";
                    };

                    Install.WantedBy = [ "default.target" ];
                  })
                ]
              ) (lib.attrsToList remote.mounts)
            ) remotesWithMounts
          ))
        ];
      })

      # ── Darwin: launchd agents ────────────────────────────────────────
      (lib.mkIf isDarwin {
        launchd.agents = lib.mkMerge [
          # Config agent: symmetric with the Linux rclone-config service.
          # See header comment for the ordering / retry strategy.
          (lib.mkIf (cfg.remotes != { }) {
            rclone-config = {
              enable = true;
              config = {
                ProgramArguments = [ (lib.getExe rcloneConfigApp) ];
                RunAtLoad = true;
                KeepAlive = {
                  SuccessfulExit = false;
                };
                StandardOutPath = "${homeDir}/Library/Logs/rclone-config.log";
                StandardErrorPath = "${homeDir}/Library/Logs/rclone-config.log";
              }
              // lib.optionalAttrs (allSecretPaths != [ ]) {
                WatchPaths = allSecretPaths;
              };
            };
          })

          # One launchd agent per remote.mounts entry.
          (lib.listToAttrs (
            lib.concatMap (
              { name, value }:
              let
                remoteName = name;
                remote = value;
              in
              lib.mapAttrsToList (
                mountPath: mount:
                lib.nameValuePair "rclone-mount:${replaceSlashes mountPath}@${remoteName}" {
                  inherit (mount) enable;
                  config = {
                    ProgramArguments = [ "${mkDarwinMountScript remoteName mountPath mount}" ];
                    RunAtLoad = true;
                    KeepAlive = {
                      Crashed = true;
                      SuccessfulExit = false;
                    };
                    StandardOutPath = "${homeDir}/Library/Logs/rclone-mount-${remoteName}.log";
                    StandardErrorPath = "${homeDir}/Library/Logs/rclone-mount-${remoteName}.log";
                    ProcessType = "Background";
                  };
                }
              ) remote.mounts
            ) remotesWithMounts
          ))
        ];
      })
    ]
  );
}
