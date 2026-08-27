{ flake, ... }:
{
  imports = flake.lib.nixosHost {
    system = "x86_64-linux";
    hostName = "zoozve";
    caps = [
      "base"
      "dev"
    ];
    modules = [ ./disk-config.nix ];
  };

  dotfiles = {
    system.autoUpgrade.enable = true;
    platform.incusVm = {
      enable = true;
      # The hypervisor is not fully trusted. Disable every agent API that can
      # execute commands or read guest files (which would expose agenix
      # secrets under /run/agenix), and interface state (VM IPs in incus list).
      agent.features = {
        exec = false;
        files = false;
        state = false;
      };
    };
  };

  system.stateVersion = "26.05";
}
