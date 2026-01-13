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

  pkgs = import nixpkgs {
    inherit system;
    config.allowUnfree = true;
    overlays = [
      (import ../overlays/fix-1password.nix)
      (import ../overlays/mk-op-wrapped.nix)
      (final: prev: {
        unstable = import nixpkgs-unstable {
          inherit system;
          config = prev.config;
        };
      })
      # Add llm-agents packages (daily builds)
      (final: prev: {
        llm-agents = llm-agents.packages.${system};
      })
    ];
  };

  # Read username and home directory from environment (requires --impure)
  username = builtins.getEnv "USER";
  homeDirectory = builtins.getEnv "HOME";
in
home-manager.lib.homeManagerConfiguration {
  inherit pkgs;
  modules = [
    ./base.nix
    ./dev.nix
    {
      home.username = username;
      home.homeDirectory = homeDirectory;
    }
    {
      targets.genericLinux.enable = true;
    }
  ];
}
