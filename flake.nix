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
    {
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

      nixosConfigurations = {
        pc = import ./hosts/pc {
          inherit
            self
            nixpkgs
            nixpkgs-unstable
            home-manager
            ;
        };
      };
    };
}
