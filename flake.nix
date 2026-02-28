{
  description = "Nix Configurations";

  nixConfig = {
    extra-substituters = [
      "https://cache.numtide.com"
      "https://nix-community.cachix.org"
      "https://niri.cachix.org"
      "https://whexy.cachix.org"
    ];
    extra-trusted-public-keys = [
      "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "niri.cachix.org-1:Wv0OmO7PsuocRKzfDoJ3mulSl7Z6oezYhGhR+3W2964="
      "whexy.cachix.org-1:XzmCWs+qh3vMtB4p1joLM+ajn5z/UYgZOyxykzEDV2o="
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

    # Niri Wayland compositor
    niri = {
      url = "github:sodiboo/niri-flake";
    };

    # Secret management with age encryption
    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
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
      mkHome = import ./mkhome.nix {
        inherit inputs;
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

        remote-basic = mkHost {
          system = "x86_64-linux";
          hardware = "qemu-x86_64";
          hostname = "remote-basic";
          username = "whexy";
          caps = [
            "base"
          ];
        };

        # Proxmox VM image (use `just build-proxmox remote-service`)
        remote-service = mkHost {
          system = "x86_64-linux";
          hardware = "proxmox";
          hostname = "remote-service";
          username = "whexy";
          caps = [
            "base"
            "service"
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
          ];
        };

        # Desktop VM images - UTM (QEMU) backend
        # Build with: just build-desktop utm [x86_64|aarch64]
        desktop-utm-x86_64 = mkHost {
          system = "x86_64-linux";
          hardware = "vm-desktop-utm";
          hostname = "desktop";
          username = "whexy";
          caps = [
            "base"
            "dev"
            "gui"
          ];
        };

        desktop-utm-aarch64 = mkHost {
          system = "aarch64-linux";
          hardware = "vm-desktop-utm";
          hostname = "desktop";
          username = "whexy";
          caps = [
            "base"
            "dev"
            "gui"
          ];
        };

        # Desktop VM images - VMware backend
        # Build with: just build-desktop vmware [x86_64|aarch64]
        desktop-vmware-x86_64 = mkHost {
          system = "x86_64-linux";
          hardware = "vm-desktop-vmware";
          hostname = "desktop";
          username = "whexy";
          caps = [
            "base"
            "dev"
            "gui"
          ];
        };

        desktop-vmware-aarch64 = mkHost {
          system = "aarch64-linux";
          hardware = "vm-desktop-vmware";
          hostname = "desktop";
          username = "whexy";
          caps = [
            "base"
            "dev"
            "gui"
          ];
        };
      };

      # Standalone home-manager configurations
      homeConfigurations = {
        home = mkHome {
          system = "x86_64-linux";
        };

        home-aarch64 = mkHome {
          system = "aarch64-linux";
        };

        home-base = mkHome {
          system = "x86_64-linux";
          caps = [ "base" ];
        };

        home-base-aarch64 = mkHome {
          system = "aarch64-linux";
          caps = [ "base" ];
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
