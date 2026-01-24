{
  description = "Nix Configurations";

  nixConfig = {
    extra-substituters = [
      "https://cache.numtide.com"
      "https://nix-community.cachix.org"
    ];
    extra-trusted-public-keys = [
      "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    ];
  };

  inputs = {
    # NixOS / Linux
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

    # Darwin (macOS)
    nixpkgs-darwin.url = "github:NixOS/nixpkgs/nixpkgs-25.11-darwin";

    # Shared unstable overlay input
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

    # Home Manager (NixOS/Linux)
    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Home Manager (Darwin)
    home-manager-darwin = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs-darwin";
    };

    nix-darwin = {
      url = "github:nix-darwin/nix-darwin/nix-darwin-25.11";
      inputs.nixpkgs.follows = "nixpkgs-darwin";
    };

    # WSL installer
    nixos-wsl = {
      url = "github:nix-community/NixOS-WSL";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # AI coding agents (daily builds)
    llm-agents = {
      url = "github:numtide/llm-agents.nix";
    };

    # Neovim nightly builds
    neovim-nightly-overlay = {
      url = "github:nix-community/neovim-nightly-overlay";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      nixpkgs-darwin,
      nixpkgs-unstable,
      home-manager,
      home-manager-darwin,
      nix-darwin,
      ...
    }@inputs:
    let
      mkHost = import ./mkhost.nix {
        inherit inputs self;
      };
    in
    {
      # macOS (nix-darwin) configurations
      darwinConfigurations = {
        mbp = mkHost {
          system = "aarch64-darwin";
          hardware = "macos-laptop";
          hostname = "mbp";
          username = "whexy";
          darwin = true;
          caps = [
            "base"
            "dev"
            "gui"
            "macos"
          ];
        };

        mini = mkHost {
          system = "aarch64-darwin";
          hardware = "macos-desktop";
          hostname = "mini";
          username = "whexy";
          darwin = true;
          caps = [
            "base"
            "dev"
            "gui"
            "macos"
          ];
        };
      };

      # NixOS configurations
      nixosConfigurations = {
        remote-dev = mkHost {
          system = "x86_64-linux";
          hardware = "qemu-x86_64";
          hostname = "remote-dev";
          username = "whexy";
          caps = [
            "base"
            "dev"
          ];
        };

        wsl = mkHost {
          system = "x86_64-linux";
          hardware = "wsl";
          hostname = "nixos-wsl";
          username = "whexy";
          wsl = true;
          caps = [
            "base"
            "dev"
            "gui"
          ];
        };
      };

      # Standalone home-manager configurations
      homeConfigurations = {
        home = import ./home/standalone.nix {
          inherit
            nixpkgs
            nixpkgs-unstable
            home-manager
            ;
          llm-agents = inputs.llm-agents;
          neovim-nightly-overlay = inputs.neovim-nightly-overlay;
          system = "x86_64-linux";
        };

        home-aarch64 = import ./home/standalone.nix {
          inherit
            nixpkgs
            nixpkgs-unstable
            home-manager
            ;
          llm-agents = inputs.llm-agents;
          neovim-nightly-overlay = inputs.neovim-nightly-overlay;
          system = "aarch64-linux";
        };
      };

      # Portable packages
      packages.x86_64-linux.portable-nvim = import ./portable-nvim.nix {
        pkgs = import nixpkgs {
          system = "x86_64-linux";
          config.allowUnfree = true;
        };
      };
    };
}
