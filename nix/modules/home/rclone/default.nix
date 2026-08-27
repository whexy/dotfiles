# Rclone remote mounts — single declarative definition for all platforms.
#
#   nas:    WebDAV  → ~/mnt/nas
#   b2:     B2 + crypt → ~/mnt/b2  (b2-raw is the underlying backend)
#
# Linux:  systemd user services (FUSE via `rclone mount`).
# macOS:  launchd agents (native NFS via `rclone nfsmount`, no macFUSE).
#
# Both platforms are driven by the same `programs.rclone.remotes` data,
# wired up by ./services.nix.
#
# This file also re-declares the `programs.rclone.*` options (a fork of
# home-manager's upstream module that ./services.nix reads) and gates the
# whole feature behind `dotfiles.rclone.enable`.
#
# ── Cloudflare Access on the NAS ─────────────────────────────────────
# The NAS WebDAV endpoint is fronted by a Cloudflare Tunnel and gated by a
# Cloudflare Access "Service Auth" policy. Requests must carry two HTTP
# headers:
#
#     CF-Access-Client-Id:     <from secrets/cf-access-dotfiles-id.age>
#     CF-Access-Client-Secret: <from secrets/cf-access-dotfiles-secret.age>
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
  cfg = config.dotfiles.rclone;

  isUsingSecretProvisioner = name: config ? "${name}" && config."${name}".secrets != { };
in
{
  disabledModules = [ "programs/rclone.nix" ];

  imports = [
    (lib.mkRemovedOptionModule [ "programs" "rclone" "writeAfter" ] ''
      The writeAfter option has been removed because rclone configuration is now handled by a
      systemd service (Linux) or launchd agent (Darwin) instead of an activation script.
    '')
    ./services.nix
  ];

  options = {
    dotfiles.rclone.enable = lib.mkEnableOption "rclone";

    programs.rclone = {
      package = lib.mkPackageOption pkgs "rclone" { };

      remotes = lib.mkOption {
        type = lib.types.attrsOf (
          lib.types.submodule {
            options = {
              config = lib.mkOption {
                type =
                  with lib.types;
                  let
                    baseType = attrsOf (
                      nullOr (oneOf [
                        bool
                        int
                        float
                        str
                      ])
                    );

                    remoteConfigType = addCheck baseType (lib.hasAttr "type") // {
                      name = "rcloneRemoteConfig";
                      description = "An attribute set containing a remote type and options.";
                    };
                  in
                  remoteConfigType;
                default = { };
                description = ''
                  Regular configuration options as described in rclone's documentation
                  <https://rclone.org/docs/>. When specifying options follow the formatting
                  process outlined here <https://rclone.org/docs/#config-config-file>, namely:
                   - Remove the leading double-dash (--) from the rclone option name
                   - Replace hyphens (-) with underscores (_)
                   - Convert to lowercase
                   - Use the resulting string as your configuration key

                  Security Note: Always use the {option}`secrets` option for sensitive data
                  instead of the {option}`config` option to prevent exposing credentials to
                  the world-readable Nix store.
                '';
                example = lib.literalExpression ''
                  {
                    type = "mega";
                    user = "you@example.com";
                    hard_delete = true;
                  }'';
              };

              secrets = lib.mkOption {
                type = with lib.types; attrsOf str;
                default = { };
                description = ''
                  Sensitive configuration values such as passwords, API keys, and tokens. These
                  must be provided as file paths to the secrets, which will be read at activation
                  time.

                  On Darwin, these paths are also installed as launchd `WatchPaths` for the
                  `rclone-config` agent, so changes (e.g. secret rotation) automatically
                  re-render rclone.conf.
                '';
                example = lib.literalExpression ''
                  {
                    password = "/run/secrets/password";
                    api_key = config.age.secrets.api-key.path;
                  }'';
              };

              mounts = lib.mkOption {
                type =
                  with lib.types;
                  attrsOf (
                    lib.types.submodule {
                      options = {
                        enable = lib.mkEnableOption "this mount";

                        logLevel = lib.mkOption {
                          type = lib.types.nullOr (
                            lib.types.enum [
                              "ERROR"
                              "NOTICE"
                              "INFO"
                              "DEBUG"
                            ]
                          );
                          default = null;
                          example = "INFO";
                          description = ''
                            Set the log-level.
                            See: https://rclone.org/docs/#logging
                          '';
                        };

                        mountPoint = lib.mkOption {
                          type = lib.types.str;
                          default = null;
                          description = ''
                            A local file path specifying the location of the mount point.
                          '';
                          example = "/home/alice/my-remote";
                        };

                        options = lib.mkOption {
                          type =
                            with lib.types;
                            attrsOf (
                              nullOr (oneOf [
                                bool
                                int
                                float
                                str
                              ])
                            );
                          default = { };
                          apply = lib.mergeAttrs {
                            vfs-cache-mode = "full";
                            cache-dir = "%C/rclone";
                          };
                          description = ''
                            An attribute set of option values passed to `rclone mount`
                            (Linux) / `rclone nfsmount` (Darwin). To set a boolean option,
                            assign it `true` or `false`. See
                            <https://nixos.org/manual/nixpkgs/stable/#function-library-lib.cli.toCommandLineShellGNU>
                            for more details on the format.

                            Some caching options are set by default, namely
                            `vfs-cache-mode = "full"` and `cache-dir`. These can be
                            overridden if desired. On Darwin, `%C/rclone` is rewritten to
                            `~/Library/Caches/rclone`.
                          '';
                        };
                      };
                    }
                  );
                default = { };
                description = ''
                  An attribute set mapping remote file paths to their corresponding mount
                  point configurations.
                '';
                example = lib.literalExpression ''
                  {
                    "path/to/files" = {
                      enable = true;
                      mountPoint = "/home/alice/rclone-mount";
                      options = {
                        dir-cache-time = "5000h";
                        poll-interval = "10s";
                        umask = "002";
                        user-agent = "Laptop";
                      };
                    };
                  }
                '';
              };
            };
          }
        );
        default = { };
        description = ''
          An attribute set of remote configurations. Each remote consists of regular
          configuration options and optional secrets.

          See <https://rclone.org/docs/> for more information on configuring specific
          remotes.
        '';
        example = lib.literalExpression ''
          {
            b2 = {
              config = {
                type = "b2";
                hard_delete = true;
              };
              secrets = {
                account = config.sops.secrets.b2-acc-id.path;
                key = config.age.secrets.b2-key.path;
              };
            };
          }'';
      };

      requiresUnit = lib.mkOption {
        type = with lib.types; nullOr str;
        default =
          lib.foldlAttrs
            (
              acc: prov: svc:
              if isUsingSecretProvisioner prov then svc else acc
            )
            null
            {
              "sops" = "sops-nix.service";
              "age" = "agenix.service";
            };
        example = "agenix.service";
        description = ''
          The name of a systemd user service that must complete before the rclone
          configuration file is written. Linux-only; ignored on Darwin (which uses
          `WatchPaths` instead).

          When using sops-nix or agenix, this value is set automatically.
        '';
      };
    };
  };

  config = lib.mkIf cfg.enable (
    let
      homeDir = config.home.homeDirectory;

      cfIdPath = config.age.secrets.cf-access-dotfiles-id.path;
      cfSecretPath = config.age.secrets.cf-access-dotfiles-secret.path;

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
        (lib.cli.toCommandLineShellGNU { } nasMountOptions)
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
          ${lib.cli.toCommandLineShellGNU { } nasMountOptionsDarwin} \
          "nas:/" "${nasMountPoint}"
      '';
    in
    {
      age.secrets = {
        nas-webdav-pass.file = ../../../../secrets/nas-webdav-pass.age;
        cf-access-dotfiles-id.file = ../../../../secrets/cf-access-dotfiles-id.age;
        cf-access-dotfiles-secret.file = ../../../../secrets/cf-access-dotfiles-secret.age;
        b2-account.file = ../../../../secrets/b2-account.age;
        b2-key.file = ../../../../secrets/b2-key.age;
        b2-crypt-password.file = ../../../../secrets/b2-crypt-password.age;
      };

      programs.rclone = {
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
  );
}
