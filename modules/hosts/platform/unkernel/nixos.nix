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

  launcherPkgs = inputs.nixpkgs.legacyPackages.${cfg.launcherSystem};

  # Match both halves of the relay protocol with the pinned unkernel demo.
  wlandVersion = "0.1.0-261125-0023837";
  wlandWeb = launcherPkgs.fetchzip {
    url = "https://registry.npmjs.org/wland/-/wland-${wlandVersion}.tgz";
    hash = "sha256-rwebqgg7VwFsMxOZht4KhC1nLJjB5f1G/5FkTa/YxEo=";
  };
  wlandRelay = pkgs.stdenvNoCC.mkDerivation {
    pname = "wlandr";
    version = wlandVersion;
    src = pkgs.fetchurl {
      url = "https://github.com/pithings/wland/releases/download/v${wlandVersion}/wlandr-link-linux-arm64.tar.gz";
      hash = "sha256-E1tMxpmWqe5EPO2otxIsLZ7ekQHvOMjbYalHdWNrqt0=";
    };
    sourceRoot = ".";
    installPhase = ''
      runHook preInstall
      install -Dm755 wlandr "$out/bin/wlandr"
      runHook postInstall
    '';
  };

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
      pkgs = launcherPkgs;
      waylandWeb = if cfg.wayland.enable then wlandWeb else null;
      inherit (flake.packages.${cfg.launcherSystem}) unkernel wisp-server wxstack;
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
        after = [
          "systemd-user-sessions.service"
          "home-manager-${config.dotfiles.host.username}.service"
        ];
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

      unkernel-wayland = lib.mkIf cfg.wayland.enable {
        description = "Wayland relay to the browser compositor";
        wantedBy = [ "multi-user.target" ];
        unitConfig.ConditionPathExists = "/dev/kwshm";
        environment.XDG_RUNTIME_DIR = "/run/tabos-wayland";
        serviceConfig = {
          User = config.dotfiles.host.username;
          RuntimeDirectory = "tabos-wayland";
          RuntimeDirectoryMode = "0700";
          # Leave the browser compositor unloaded until a Wayland client connects.
          ExecStart = "${wlandRelay}/bin/wlandr --link vsock:2:1023 --buffers kwshm --link-on-demand --display wayland-0";
          Restart = "on-failure";
        };
      };
    };
  };
}
