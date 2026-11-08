{
  config,
  options,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.dotfiles.platform.wsl;
in
{
  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        assertions = [
          {
            assertion = config.dotfiles.host.wsl;
            message = "dotfiles.platform.wsl needs the NixOS-WSL module; set wsl = true in flake.lib.nixosHost.";
          }
        ];

        # WSL has no Wi-Fi hardware (Windows owns networking), so
        # NetworkManager/wpa_supplicant are unnecessary and wpa_supplicant
        # fails on every activation switch.
        dotfiles.network.networkmanager.enable = lib.mkForce false;
      }

      # The option exists only where nixosHost imports NixOS-WSL.
      (lib.optionalAttrs (options ? wsl) {
        wsl = {
          enable = true;
          defaultUser = config.dotfiles.host.username;
          startMenuLaunchers = true;
          wslConf.automount.root = "/mnt";
          interop.register = true;
        };
      })

      # https://yomaq.github.io/posts/nvidia-on-nixos-wsl-ollama-up-24-7-on-your-gaming-pc/
      (lib.mkIf cfg.nvidia.enable {
        environment.sessionVariables = {
          CUDA_PATH = "${pkgs.cudatoolkit}";
          LD_LIBRARY_PATH = [
            "/usr/lib/wsl/lib"
          ];
          MESA_D3D12_DEFAULT_ADAPTER_NAME = "Nvidia";
        };

        hardware.nvidia-container-toolkit = {
          enable = true;
          mount-nvidia-executables = false;
          suppressNvidiaDriverAssertion = true;
        };

        systemd.services = {
          # The nixpkgs nvidia-container-toolkit module ships its own CDI
          # generator (wantedBy multi-user.target) whose auto-discovery can't
          # find the driver on WSL (it lives in /usr/lib/wsl/lib, mounted by
          # Windows), so it fails on every activation. Our custom generator
          # below already handles CDI for docker; neutralize the module's unit.
          nvidia-container-toolkit-cdi-generator = {
            wantedBy = lib.mkForce [ ];
            requiredBy = lib.mkForce [ ];
          };
          nvidia-cdi-generator = {
            description = "Generate nvidia cdi";
            wantedBy = [ "docker.service" ];
            serviceConfig = {
              Type = "oneshot";
              ExecStart = "${pkgs.nvidia-docker}/bin/nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml --nvidia-ctk-path=${pkgs.nvidia-container-toolkit}/bin/nvidia-ctk";
            };
          };
        };

        virtualisation.docker = {
          daemon.settings.features.cdi = true;
          daemon.settings.cdi-spec-dirs = [ "/etc/cdi" ];
        };
      })
    ]
  );
}
