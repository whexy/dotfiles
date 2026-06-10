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
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixpkgs-darwin.url = "github:NixOS/nixpkgs/nixpkgs-26.05-darwin";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager-darwin = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs-darwin";
    };

    nix-darwin = {
      url = "github:nix-darwin/nix-darwin/nix-darwin-26.05";
      inputs.nixpkgs.follows = "nixpkgs-darwin";
    };

    nixos-wsl = {
      url = "github:nix-community/NixOS-WSL";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-index-database = {
      url = "github:nix-community/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    git-hooks = {
      url = "github:cachix/git-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    renpho-health = {
      url = "github:whexy/renpho-health-nix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.blueprint.follows = "blueprint";
    };

    hunk = {
      url = "github:modem-dev/hunk";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    blueprint = {
      url = "github:numtide/blueprint";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    llm-agents = {
      url = "github:numtide/llm-agents.nix";
      inputs = {
        nixpkgs.follows = "nixpkgs-unstable";
        blueprint.follows = "blueprint";
        treefmt-nix.follows = "treefmt-nix";
      };
    };

    niri = {
      url = "github:sodiboo/niri-flake";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
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

      # eachSystem f calls f system pkgs for each supported system.
      # Darwin x86_64 is intentionally excluded (no supported hardware).
      eachSystem =
        f:
        nixpkgs.lib.genAttrs [
          "x86_64-linux"
          "aarch64-linux"
          "aarch64-darwin"
        ] (system: f system nixpkgs.legacyPackages.${system});
      treefmtEval = eachSystem (_system: pkgs: treefmt-nix.lib.evalModule pkgs ./treefmt.nix);

      # Single source of truth for format + lint, shared by the devShell
      # (installs hooks on entry) and `checks.<system>.pre-commit` (CI).
      preCommit = eachSystem (
        system: _pkgs:
        inputs.git-hooks.lib.${system}.run {
          src = self;
          hooks = {
            treefmt = {
              enable = true;
              package = treefmtEval.${system}.config.build.wrapper;
            };
            statix.enable = true;
            nil.enable = true;
            deadnix.enable = true;
          };
        }
      );
    in
    {
      # for `nix fmt`
      formatter = eachSystem (system: _pkgs: treefmtEval.${system}.config.build.wrapper);

      # for `nix flake check`
      checks = eachSystem (
        system: _pkgs: {
          pre-commit = preCommit.${system};
        }
      );

      # `nix develop` / direnv: tools on PATH + installs git pre-commit hooks
      devShells = eachSystem (
        system: pkgs: {
          default = pkgs.mkShell {
            packages = [
              pkgs.just
              # Nix
              pkgs.nixfmt
              pkgs.statix
              pkgs.nil
              pkgs.nixd
              pkgs.deadnix
              # Other languages present in this repo
              pkgs.stylua
              pkgs.prettier
              pkgs.shfmt
              pkgs.taplo
            ];
            shellHook = preCommit.${system}.shellHook;
          };
        }
      );

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

        # lab - moore server dev VM (unprivileged user, nix-portable + KVM)
        # Run on moore with:
        #   export NIX_DISK_IMAGE=/tmp/moore-vm-$USER.qcow2
        #   nix run .#nixosConfigurations.moore.config.system.build.vm
        # Then: ssh -p 2222 whexy@localhost
        moore = mkHost {
          system = "x86_64-linux";
          hardware = "moore-vm";
          hostname = "moore-vm";
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
