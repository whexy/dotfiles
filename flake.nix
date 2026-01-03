{
  description = "Nix Configurations";

  nixConfig = {
    extra-substituters = [ "https://cache.numtide.com" ];
    extra-trusted-public-keys = [ "numtide.cachix.org-1:2ps1kLBUWjxIneOy1Ber+6DVdnZhm2AqJvta27H8eQw=" ];
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
    }:
    let
      # Helper to create standalone home-manager configurations
      mkHomeConfiguration =
        { system, username, homeDirectory }:
        let
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = true;
            overlays = [
              (final: prev: {
                unstable = import nixpkgs-unstable {
                  inherit system;
                  config.allowUnfree = true;
                };
              })
              (import ./overlays/mk-op-wrapped.nix)
            ];
          };
        in
        home-manager.lib.homeManagerConfiguration {
          inherit pkgs;
          modules = [
            ./home/standalone.nix
            {
              home.username = username;
              home.homeDirectory = homeDirectory;
            }
          ];
        };
    in
    {
      # macOS (nix-darwin) configurations
      darwinConfigurations = {
        mbp = import ./hosts/mbp {
          inherit
            self
            nixpkgs-unstable
            nix-darwin
            ;
          nixpkgs = nixpkgs-darwin;
          home-manager = home-manager-darwin;
        };
      };

      # NixOS configurations
      nixosConfigurations = {
        remote-dev = import ./hosts/remote-dev {
          inherit
            self
            nixpkgs
            nixpkgs-unstable
            home-manager
            ;
        };
      };

      # Standalone home-manager configurations (for non-NixOS Linux)
      homeConfigurations = {
        # Default: x86_64-linux for user "whexy"
        "whexy@linux" = mkHomeConfiguration {
          system = "x86_64-linux";
          username = "whexy";
          homeDirectory = "/home/whexy";
        };

        # aarch64-linux variant
        "whexy@linux-aarch64" = mkHomeConfiguration {
          system = "aarch64-linux";
          username = "whexy";
          homeDirectory = "/home/whexy";
        };
      };
    };
}
