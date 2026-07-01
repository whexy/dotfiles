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
    flake.nixosModules.user-whexy
    flake.nixosModules.platform-qemu-guest-uefi-disko
  ];

  nixpkgs.hostPlatform = "x86_64-linux";
  networking.hostName = "remote-dev";

  _module.args = { inherit username wsl; };

  home-manager = {
    backupFileExtension = "backup";
    extraSpecialArgs = {
      inherit inputs flake wsl;
      darwin = false;
    };
  };
}
