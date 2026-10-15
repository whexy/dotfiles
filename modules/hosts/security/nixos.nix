{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.dotfiles.security;
  username = config.dotfiles.host.username;

  # The PIN hash and the failed-attempt log share this home-relative directory
  # because swaylock authenticates as the locked user, not as root. Anything
  # running as that user can read or replace them, which is acceptable only
  # while the PIN unlocks nothing beyond swaylock.
  lockPinDir = ".local/state/lock-pin";
  lockPinMaxFailures = 5;

  lockPin = pkgs.writeShellApplication {
    name = "lock-pin";
    runtimeInputs = with pkgs; [
      coreutils
      openssl
    ];
    text = ''
      dir=$HOME/${lockPinDir}
      case ''${1:-} in
        set)
          read -rsp "New PIN (4-12 digits): " pin
          echo
          if [[ ! $pin =~ ^[0-9]{4,12}$ ]]; then
            echo "lock-pin: a PIN is 4 to 12 digits" >&2
            exit 1
          fi
          read -rsp "Repeat PIN: " repeat
          echo
          if [[ $pin != "$repeat" ]]; then
            echo "lock-pin: the PINs differ" >&2
            exit 1
          fi
          umask 077
          mkdir -p "$dir"
          openssl passwd -6 -stdin <<<"$pin" >"$dir/hash"
          rm -f "$dir/failures"
          echo "lock-pin: swaylock now accepts this PIN"
          ;;
        remove)
          rm -f "$dir/hash" "$dir/failures"
          ;;
        *)
          echo "usage: lock-pin set|remove" >&2
          exit 2
          ;;
      esac
    '';
  };

  # Runs under pam_exec with the typed secret on stdin; exit 0 accepts it.
  lockPinCheck = pkgs.writeShellApplication {
    name = "lock-pin-check";
    runtimeInputs = with pkgs; [
      coreutils
      getent
      openssl
    ];
    text = ''
      home=$(getent passwd "$PAM_USER" | cut -d: -f6)
      dir=$home/${lockPinDir}
      secret=$(cat)
      # Only digit strings are PIN attempts. Anything else is the account
      # password, which must not count against the PIN.
      [[ -f $dir/hash && $secret =~ ^[0-9]+$ ]] || exit 1
      # One line per failed attempt; a successful PIN or `lock-pin set` clears it.
      failures=$(wc -l <"$dir/failures" 2>/dev/null || echo 0)
      ((failures < ${toString lockPinMaxFailures})) || exit 1
      stored=$(<"$dir/hash")
      IFS='$' read -r _ _ salt _ <<<"$stored"
      if [[ $(openssl passwd -6 -salt "$salt" -stdin <<<"$secret") == "$stored" ]]; then
        rm -f "$dir/failures"
        exit 0
      fi
      echo >>"$dir/failures"
      exit 1
    '';
  };
in
{
  config = lib.mkMerge [
    (lib.mkIf cfg.agentPolicy.enable {
      environment.etc."claude-code/managed-settings.d/50-dotfiles.json".source =
        ../../home/agents/claude-code/settings.json;
    })

    (lib.mkIf cfg.passwordlessSudo.enable { security.sudo.wheelNeedsPassword = false; })

    (lib.mkIf cfg.onepassword.enable { programs._1password.enable = true; })

    (lib.mkIf cfg.onepasswordGui.enable {
      programs._1password-gui = {
        enable = true;
        polkitPolicyOwners = [ username ];
      };
    })

    # GNOME Keyring: implements the Secret portal for apps that need credentials
    (lib.mkIf cfg.keyring.enable { services.gnome.gnome-keyring.enable = true; })

    (lib.mkIf cfg.soteria.enable { security.soteria.enable = true; })

    (lib.mkIf cfg.fail2ban.enable { services.fail2ban.enable = true; })

    # The PIN applies to the swaylock service only; login, sudo, and polkit
    # still require the account password. A rejected PIN falls through to
    # pam_unix, which reuses the token pam_exec stored because swaylock
    # answers a single prompt per attempt.
    (lib.mkIf cfg.lockPin.enable {
      environment.systemPackages = [ lockPin ];
      security.pam.services.swaylock.rules.auth.lock-pin = {
        order = config.security.pam.services.swaylock.rules.auth.unix.order - 10;
        control = "sufficient";
        modulePath = "${config.security.pam.package}/lib/security/pam_exec.so";
        args = [
          "quiet"
          "quiet_log"
          "expose_authtok"
          (lib.getExe lockPinCheck)
        ];
      };
    })
  ];
}
