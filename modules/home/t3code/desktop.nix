# whexy/t3code's desktop app: the pinned package on Linux, the fork's signed
# build on macOS, and a client of the server service wherever that runs.
{
  config,
  lib,
  pkgs,
  perSystem,
  ...
}:
let
  cfg = config.dotfiles.t3code;
  inherit (pkgs.stdenv.hostPlatform) isDarwin;

  privacy = import ./privacy.nix { inherit lib pkgs; };

  userdataSetting = import ./userdata.nix {
    inherit lib pkgs;
    inherit (config.home) homeDirectory;
  };

  # The desktop app's own server needs ~/.t3/userdata to itself, and the app
  # quits when the server service already holds it. Where the service runs,
  # the app starts no local environment and is a client of that server
  # instead, paired with t3-pair.
  desktopClientOnly = userdataSetting {
    name = "t3-desktop-client-only";
    file = "desktop-settings.json";
    key = "localEnvironmentEnabled";
    value = false;
  };

  # The app's updater replaces the macOS app itself, so activation installs it
  # only when it is missing or is not the fork's, such as upstream's app of the
  # same name, at the nightly the server builds. Installing as the user lets the
  # updater run without an admin prompt.
  desktopApp = "/Applications/T3 Code (Nightly).app";
  # Nothing pins the archive's hash, so only the fork's Developer ID vouches for
  # what gets installed.
  forkSignature = ''anchor apple generic and identifier "dev.whexy.t3code.desktop" and certificate leaf[subject.OU] = "26DMRHRW6Z"'';
  installDesktopApp =
    let
      inherit (perSystem.self.t3code-fork) version;
    in
    pkgs.writeShellApplication {
      name = "t3code-desktop-install";
      text = ''
        tmp=$(mktemp -d)
        trap 'rm -rf "$tmp"' EXIT

        /usr/bin/curl -fsSL --retry 3 --connect-timeout 30 --speed-limit 10240 --speed-time 60 \
          -o "$tmp/T3.zip" \
          https://github.com/whexy/t3code/releases/download/${version}/T3-Code-${version}-arm64.zip
        /usr/bin/ditto -x -k "$tmp/T3.zip" "$tmp"
        /usr/bin/codesign --verify --deep --strict -R=${lib.escapeShellArg forkSignature} \
          "$tmp/T3 Code (Nightly).app"
        rm -rf ${lib.escapeShellArg desktopApp}
        mv "$tmp/T3 Code (Nightly).app" ${lib.escapeShellArg desktopApp}
      '';
    };
in
{
  config = lib.mkIf (cfg.enable && cfg.desktop.enable) {
    home = {
      # The app's bundled server reads the privacy switches from the app's
      # environment. The URL-handler entry the app writes must run this
      # wrapper, not the package's own program, or links open it unwrapped.
      # The macOS app runs unwrapped: the policy covers it wherever the server
      # service runs, and it is a client of that server.
      packages = lib.optional (!isDarwin) (
        privacy.wrapWith {
          T3CODE_DESKTOP_LAUNCHER_PATH = "${placeholder "out"}/bin/t3code-desktop";
        } perSystem.self.t3code-desktop-nightly
      );

      activation =
        lib.optionalAttrs cfg.server.enable {
          t3codeDesktopClientOnly = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
            run ${lib.getExe desktopClientOnly}
          '';
        }
        // lib.optionalAttrs isDarwin {
          t3codeDesktopApp = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
            if ! /usr/bin/codesign --verify -R=${lib.escapeShellArg forkSignature} ${lib.escapeShellArg desktopApp} 2>/dev/null; then
              run ${lib.getExe installDesktopApp} || warnEcho "T3 Code was not installed; the next activation retries"
            fi
          '';
        };
    };
  };
}
