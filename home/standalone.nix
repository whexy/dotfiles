# Standalone home-manager configuration for non-NixOS Linux systems
# Note: This configuration uses impure evaluation to read your username and home directory
{
  nixpkgs,
  nixpkgs-unstable,
  home-manager,
  llm-agents,
  system,
}:
let
  nixpkgsSettings = import ../overlays/nixpkgs-settings.nix {
    inputs = {
      inherit nixpkgs nixpkgs-unstable llm-agents;
    };
    tags = [
      "unstable"
      "llm-tools"
      "op-wrap"
      "op-fakeroot"
    ];
  };

  pkgs = import nixpkgs {
    inherit system;
    inherit (nixpkgsSettings) config overlays;
  };

  # Read username and home directory from environment (requires --impure)
  username = builtins.getEnv "USER";
  homeDirectory = builtins.getEnv "HOME";
in
home-manager.lib.homeManagerConfiguration {
  inherit pkgs;
  extraSpecialArgs = {
    wsl = false;
  };
  modules = [
    ./base.nix
    ./dev.nix
    {
      home.username = username;
      home.homeDirectory = homeDirectory;
    }
    {
      targets.genericLinux.enable = true;
      # Disable GPU integration - it's not needed for standalone configs (typically remote servers)
      # and some GPU packages (like libvdpau-va-gl) have dependencies not available on aarch64
      targets.genericLinux.gpu.enable = false;
    }
  ];
}
