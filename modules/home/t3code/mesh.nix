# t3-mesh links every T3 Code server in flake.lib.t3.mesh to every other one
# and renews each link before its 30-day session runs out. One host runs it
# weekly and reaches the others over Tailscale SSH.
{
  config,
  lib,
  pkgs,
  flake,
  ...
}:
let
  cfg = config.dotfiles.t3code;
  inherit (flake.lib.t3) mesh tailnetPort;

  urls =
    name: f:
    "declare -A ${name}=(${
      lib.concatMapStringsSep " " (host: "[${host}]=${lib.escapeShellArg (f host)}") mesh
    })";

  command = pkgs.writeShellApplication {
    name = "t3-mesh";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.curl
      pkgs.jq
    ];
    text = ''
      t3=${lib.getExe' cfg.finalPackage "t3"}
      members=(${lib.escapeShellArgs mesh})
      ${urls "tailnet_url" (host: "https://${flake.lib.tailnetHost host}:${toString tailnetPort}")}
      ${urls "public_url" (host: "https://${flake.lib.publicHost "t3" host}")}
      alert_url=${lib.escapeShellArg flake.lib.t3.alertWebhook}
      # Nix's curl knows no CA bundle on macOS or non-NixOS Linux.
      export CURL_CA_BUNDLE=''${CURL_CA_BUNDLE:-${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt}
    ''
    + builtins.readFile ./mesh.sh;
  };
in
{
  options.dotfiles.t3code.mesh.enable = lib.mkEnableOption ''
    t3-mesh on this host, with a weekly timer: it links every T3 Code server
    in `flake.lib.t3.mesh` to every other one and renews links that expire
    within two weeks. Enable it on one host only
  '';

  config = lib.mkIf (cfg.enable && cfg.mesh.enable) {
    assertions = [
      {
        assertion = pkgs.stdenv.hostPlatform.isLinux;
        message = "dotfiles.t3code.mesh runs from a systemd user timer, so it needs a Linux host.";
      }
    ];

    home.packages = [ command ];

    systemd.user.services.t3-mesh = {
      Unit.Description = "Link the T3 Code mesh and renew its links";
      Service = {
        Type = "oneshot";
        ExecStart = lib.getExe command;
        # ssh is the user's configured one, from the profiles.
        Environment = [ "PATH=${config.home.profileDirectory}/bin:/run/current-system/sw/bin" ];
      };
    };
    # A calendar timer, not an interval one: an interval restarts with each
    # boot, so a host rebooted more often than weekly would never run it.
    systemd.user.timers.t3-mesh = {
      Unit.Description = "Renew the T3 Code mesh weekly";
      Timer = {
        OnCalendar = "weekly";
        Persistent = true;
        RandomizedDelaySec = "1h";
      };
      Install.WantedBy = [ "timers.target" ];
    };
  };
}
