{ flake, inputs, ... }:
let
  username = "whexy";
  wsl = true;
in
{
  imports = [
    inputs.disko.nixosModules.disko
    inputs.nixos-wsl.nixosModules.wsl
    flake.nixosModules.nix-settings
    flake.nixosModules.options-monitors
    flake.nixosModules.options-keyboards
    flake.nixosModules.options-display
    flake.nixosModules.base
    flake.nixosModules.dev
    flake.nixosModules.user-whexy
    ./hardware.nix
  ];

  nixpkgs = {
    hostPlatform = "x86_64-linux";
    overlays = [
      flake.lib.overlays.op-wsl
      flake.lib.overlays.ssh-wsl
    ];
  };
  networking.hostName = "nixos-wsl";

  _module.args = { inherit username wsl; };

  home-manager = {
    backupFileExtension = "backup";
    extraSpecialArgs = {
      inherit inputs flake wsl;
      darwin = false;
    };
  };
}
