# Host metadata. flake.lib.nixosHost and darwinHost assign it from their
# arguments; Home Manager modules read it as osConfig.dotfiles.host.
{ config, lib, ... }:
{
  options.dotfiles.host = {
    hostName = lib.mkOption {
      type = lib.types.str;
      default = config.networking.hostName;
      defaultText = lib.literalExpression "config.networking.hostName";
      description = "Host output and runtime hostname.";
    };
    system = lib.mkOption {
      type = lib.types.str;
      default = config.nixpkgs.hostPlatform.system;
      defaultText = lib.literalExpression "config.nixpkgs.hostPlatform.system";
      description = "Host platform, e.g. x86_64-linux.";
    };
    username = lib.mkOption {
      type = lib.types.str;
      default = "whexy";
      description = "Primary user for this host.";
    };
    wsl = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether this host runs under WSL.";
    };
  };
}
