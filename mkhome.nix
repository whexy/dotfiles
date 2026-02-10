# Function to create a standalone home-manager configuration
# Note: This configuration uses impure evaluation to read your username and home directory
{
  inputs,
}:
{
  system,
  caps ? [
    "base"
    "dev"
  ],
}:

let
  lib = inputs.nixpkgs.lib;

  # Derive nixpkgs tags from caps
  # Mapping: base -> unstable, dev -> llm-tools
  nixpkgsTags = lib.flatten [
    (lib.optional (builtins.elem "base" caps) "unstable")
    (lib.optionals (builtins.elem "dev" caps) [
      "llm-tools"
    ])
  ];

  nixpkgsSettings = import ./overlays/nixpkgs-settings.nix {
    inherit inputs;
    tags = nixpkgsTags;
  };

  pkgs = import inputs.nixpkgs {
    inherit system;
    inherit (nixpkgsSettings) config overlays;
  };

  # Read username and home directory from environment (requires --impure)
  username = builtins.getEnv "USER";
  homeDirectory = builtins.getEnv "HOME";

  homeConfigs = map (cap: ./home/${cap}.nix) caps;
in
inputs.home-manager.lib.homeManagerConfiguration {
  inherit pkgs;
  extraSpecialArgs = {
    darwin = false;
    wsl = false;
    inherit inputs;
  };
  modules = homeConfigs ++ [
    inputs.agenix.homeManagerModules.default
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
