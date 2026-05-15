# Function to create a standalone home-manager configuration
# Note: This configuration uses impure evaluation to read your username and home directory
{
  inputs,
}:
{
  system,
  caps,
}:

let
  inherit (inputs.nixpkgs) lib;

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
    # Agenix
    inputs.agenix.homeManagerModules.default

    # nix-index-database and comma
    inputs.nix-index-database.homeModules.default

    # Cross-platform replacement for upstream HM programs.rclone
    # (adds launchd support for Darwin). Kept in sync with mkhost.nix.
    ./home/modules/programs/rclone.nix
  ]
  ++ lib.optionals (builtins.elem "gui" caps) [
    # Renpho health (gui cap only). Mirrors mkhost.nix.
    inputs.renpho-health.homeModules.default
    inputs.renpho-health.homeModules.waybar
  ]
  ++ [

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
