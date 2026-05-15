rec {
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

    # Niri Wayland compositor
    niri = {
      url = "github:sodiboo/niri-flake";
    };

    # Declarative disk partitioning
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Secret management with age encryption
    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Nix index database for quick command search
    nix-index-database = {
      url = "github:nix-community/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Treefmt, code formatter for all
    treefmt-nix.url = "github:numtide/treefmt-nix";
    systems.url = "github:nix-systems/default";
  };

  outputs =
    {
      self,
      nixpkgs,
      systems,
      treefmt-nix,
      ...
    }@inputs:
    let
      mkHost = import ./mkhost.nix {
        inherit inputs self nixConfig;
      };
      mkHome = import ./mkhome.nix {
        inherit inputs;
      };

      eachSystem = f: nixpkgs.lib.genAttrs (import systems) (system: f nixpkgs.legacyPackages.${system});
      treefmtEval = eachSystem (pkgs: treefmt-nix.lib.evalModule pkgs ./treefmt.nix);
    in
    {
      # for `nix fmt`
      formatter = eachSystem (pkgs: treefmtEval.${pkgs.system}.config.build.wrapper);

      # for `nix flake check`
      checks = eachSystem (pkgs: {
        formatting = treefmtEval.${pkgs.system}.config.build.check self;
        statix =
          pkgs.runCommand "statix-check"
            {
              nativeBuildInputs = [ pkgs.statix ];
            }
            ''
              cp -r ${self} source
              chmod -R +w source
              statix check source
              touch $out
            '';
      });

      # macOS (nix-darwin) configurations
      darwinConfigurations = {
        mba = mkHost {
          system = "aarch64-darwin";
          hardware = "macos-laptop";
          hostname = "mba";
          username = "whexy";
          darwin = true;
          caps = [
            "base"
            "dev-lite"
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
            "dev-lite"
            "gui"
          ];
        };
      };

      # NixOS configurations
      nixosConfigurations = {
        # home - workstation (5800X)
        ord = mkHost {
          system = "x86_64-linux";
          hardware = "ord";
          hostname = "ord";
          username = "whexy";
          caps = [
            "base"
            "dev"
            "gui"
          ];
        };

        # lab - b3srv0 (9995WX)
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

        # lab - workstation (5700X)
        mvp = mkHost {
          system = "x86_64-linux";
          hardware = "qemu-x86_64";
          hostname = "mvp";
          username = "whexy";
          caps = [
            "base"
            "dev"
          ];
        };

        # home - desktop (7800X3D)
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

        # mba-nixos - laptop (Apple M5)
        mba-nixos = mkHost {
          system = "aarch64-linux";
          hardware = "mba-nixos";
          hostname = "mba-nixos";
          username = "whexy";
          caps = [
            "base"
            "dev"
            "gui"
          ];
        };

        # ------------------------
        # --- ARTIFICIAL HOSTS ---
        # ------------------------

        remote-basic = mkHost {
          system = "x86_64-linux";
          hardware = "qemu-x86_64";
          hostname = "remote-basic";
          username = "whexy";
          caps = [
            "base"
          ];
        };

        # `just build-proxmox remote-service`
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

        # `just build-desktop utm x86_64`
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

        # `just build-desktop utm aarch64`
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

        # `just build-desktop vmware x86_64`
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

        # `just build-desktop vmware aarch64`
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
          caps = [
            "base"
            "dev"
          ];
        };

        home-aarch64 = mkHome {
          system = "aarch64-linux";
          caps = [
            "base"
            "dev"
          ];
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
    };
}
