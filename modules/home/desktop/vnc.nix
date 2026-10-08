# Wayland VNC server for the NixOS desktop session.
args@{
  config,
  lib,
  pkgs,
  ...
}:
let
  osConfig = args.osConfig or null;
  enabled =
    osConfig != null
    && (osConfig.dotfiles.desktop.vnc.enable or false)
    && pkgs.stdenv.hostPlatform.isLinux;

  # Keys are per-host secrets, so they are generated on first start instead of
  # living in the Nix store.
  keyDir = "${config.xdg.stateHome}/wayvnc";

  # Clients log in with the Linux account through the `wayvnc` PAM service
  # (declared by the NixOS `programs.wayvnc` module). `relax_encryption`
  # enables Apple Diffie-Hellman auth, the only password-based security type
  # macOS Screen Sharing offers that also works with PAM.
  wayvncConfig = pkgs.writeText "wayvnc-config" ''
    address=0.0.0.0
    enable_auth=true
    enable_pam=true
    relax_encryption=true
    rsa_private_key_file=${keyDir}/rsa_key.pem
    private_key_file=${keyDir}/tls_key.pem
    certificate_file=${keyDir}/tls_cert.pem
  '';

  ensureKeys = pkgs.writeShellScript "wayvnc-ensure-keys" ''
    set -eu
    umask 077
    mkdir -p ${keyDir}
    cd ${keyDir}
    openssl=${lib.getExe pkgs.openssl}
    if [ ! -s rsa_key.pem ]; then
      $openssl genrsa -traditional -out rsa_key.pem 4096
    fi
    if [ ! -s tls_key.pem ] || [ ! -s tls_cert.pem ]; then
      $openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:secp384r1 \
        -sha384 -days 3650 -nodes -subj "/CN=$(${pkgs.hostname}/bin/hostname)" \
        -keyout tls_key.pem -out tls_cert.pem
    fi
  '';
in
{
  config = lib.mkIf enabled {
    systemd.user.services.wayvnc = {
      Unit = {
        Description = "Wayland VNC server";
        After = [ "graphical-session.target" ];
        PartOf = [ "graphical-session.target" ];
      };
      Service = {
        ExecStartPre = "${ensureKeys}";
        ExecStart = "${pkgs.wayvnc}/bin/wayvnc --config=${wayvncConfig}";
        Restart = "on-failure";
        RestartSec = 2;
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };
  };
}
