{ flake, inputs, ... }:
let
  username = "whexy";
  wsl = false;
in
{
  imports = [
    inputs.disko.nixosModules.disko
    flake.nixosModules.nix-settings
    flake.nixosModules.options-monitors
    flake.nixosModules.options-keyboards
    flake.nixosModules.options-display
    flake.nixosModules.base
    flake.nixosModules.dev
    flake.nixosModules.gui
    flake.nixosModules.user-whexy
    ./hardware.nix
  ];

  nixpkgs.hostPlatform = "x86_64-linux";
  networking.hostName = "ord";

  _module.args = { inherit username wsl; };

  home-manager = {
    backupFileExtension = "backup";
    extraSpecialArgs = {
      inherit inputs flake wsl;
      darwin = false;
    };
  };
}
