{ flake, inputs, ... }:
let
  username = "whexy";
in
{
  class = "nix-darwin";
  value = inputs.nix-darwin.lib.darwinSystem {
    system = "aarch64-darwin";
    modules = [
      flake.darwinModules.nix-settings
      flake.darwinModules.options-keyboards
      flake.darwinModules.options-display
      flake.darwinModules.base
      flake.darwinModules.dev-lite
      flake.darwinModules.gui
      flake.darwinModules.user-whexy
      inputs.home-manager-darwin.darwinModules.home-manager
      ./hardware.nix
      {
        nixpkgs.hostPlatform = "aarch64-darwin";
        networking.hostName = "mba";

        _module.args = {
          inherit username;
          wsl = false;
        };

        home-manager = {
          useGlobalPkgs = true;
          useUserPackages = true;
          backupFileExtension = "backup";
          extraSpecialArgs = {
            inherit inputs flake;
            darwin = true;
            wsl = false;
          };
          users.${username}.imports = [ ./users/whexy/home-configuration.nix ];
        };
      }
    ];
    specialArgs = {
      inherit inputs flake;
      hostName = "mba";
    };
  };
}
