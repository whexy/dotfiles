{
  config,
  flake,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.dotfiles.platform.unkernel;

  # The tools of unkernel's base system, which it lays over every image's
  # root. They belong to the kernel bundle, so the image carries none.
  kwbox = "/usr/bin/kwbox";
in
{
  config = lib.mkIf cfg.enable {
    # unkernel brings the kernel and mounts the root itself, so this host has
    # no kernel, initrd, boot loader or udev of its own.
    boot.isContainer = true;

    system.build.unkernel = import ../../../../packages/unkernel/host/launcher.nix {
      pkgs = inputs.nixpkgs.legacyPackages.${cfg.launcherSystem};
      inherit (flake.packages.${cfg.launcherSystem}) unkernel wisp-server;
      system = config;
    };

    # The wasm kernel is 32-bit and rejects these 64-bit defaults.
    boot.kernel.sysctl = {
      "vm.mmap_rnd_bits" = lib.mkForce 18;
      "kernel.pid_max" = lib.mkForce null;
    };

    # envfs mounts over /usr/bin, where the base system keeps kwbox.
    dotfiles.compat.envfs.enable = lib.mkForce false;

    # The kernel has no netfilter, and the host has no inbound network.
    dotfiles.network = {
      firewall.enable = lib.mkForce false;
      nftables.enable = lib.mkForce false;
    };

    # tailscaled prepares a firewall backend even when it is told to leave
    # the firewall alone, and its search for one fails without netfilter.
    # Named outright, the nftables backend is opened only on first use, which
    # --netfilter-mode=off never reaches.
    systemd.services.tailscaled.environment = lib.mkIf config.dotfiles.network.tailscale.enable {
      TS_DEBUG_FIREWALL_MODE = "nftables";
    };
    services.tailscale.extraSetFlags = lib.mkIf config.dotfiles.network.tailscale.enable [
      "--netfilter-mode=off"
    ];

    # The base system's DHCP client configures eth0 and writes
    # /etc/resolv.conf.
    networking = {
      useDHCP = false;
      resolvconf.enable = false;
    };

    # Mesa, for the virtio-gpu device the host offers with the display.
    hardware.graphics.enable = cfg.display.enable;

    systemd.services = {
      # The page's terminal is the console. kwbox logs in the user that
      # kw.user= on the kernel command line names.
      unkernel-console = {
        description = "Login shell on the unkernel console";
        wantedBy = [ "multi-user.target" ];
        # The shell reads the files Home Manager's activation links.
        after = [
          "systemd-user-sessions.service"
          "home-manager-${config.dotfiles.host.username}.service"
        ];
        serviceConfig = {
          ExecStart = "${kwbox} tty login";
          StandardInput = "tty";
          StandardOutput = "tty";
          StandardError = "tty";
          TTYPath = "/dev/hvc0";
          TTYReset = true;
          Restart = "always";
          RestartSec = 1;
        };
      };

      unkernel-sessions = {
        description = "Sessions the unkernel host opens over vsock";
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          ExecStart = "${kwbox} tty serve";
          Restart = "always";
          RestartSec = 1;
        };
      };

      unkernel-network = {
        description = "Network from the unkernel host";
        wantedBy = [ "multi-user.target" ];
        before = [ "network-online.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "/usr/lib/kw/net";
        };
      };

      # A container-style system has no systemd-udev-trigger, and the kernel
      # made its devices before udevd started. libinput and compositors find
      # devices only in udev's database.
      unkernel-coldplug = lib.mkIf cfg.display.enable {
        description = "Announce the unkernel host's devices to udev";
        wantedBy = [ "multi-user.target" ];
        after = [ "systemd-udevd.service" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = [
            "${config.systemd.package}/bin/udevadm trigger --action=add"
            "${config.systemd.package}/bin/udevadm settle --timeout=60"
          ];
        };
      };

      unkernel-display = lib.mkIf (cfg.display.enable && cfg.display.session != null) {
        description = "Wayland session on the unkernel display";
        wantedBy = [ "multi-user.target" ];
        after = [
          "systemd-user-sessions.service"
          "systemd-logind.service"
          "unkernel-coldplug.service"
          "home-manager-${config.dotfiles.host.username}.service"
        ];
        wants = [ "unkernel-coldplug.service" ];
        # Booted without the display, as `console` does by default.
        unitConfig.ConditionPathExists = "/dev/dri/card0";
        # The kernel has no virtual terminals, so no getty or display manager
        # can own seat0; pam_systemd takes the seat from the environment.
        environment = {
          XDG_SEAT = "seat0";
          XDG_SESSION_TYPE = "wayland";
          XDG_SESSION_CLASS = "user";
        };
        serviceConfig = {
          User = config.dotfiles.host.username;
          PAMName = "login";
          ExecStart = "${pkgs.runtimeShell} -lc ${lib.escapeShellArg "exec ${cfg.display.session}"}";
          Restart = "on-failure";
          RestartSec = 5;
        };
      };
    };
  };
}
