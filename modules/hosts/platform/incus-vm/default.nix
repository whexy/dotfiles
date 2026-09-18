# Incus virtual machine guest platform.
{ lib, ... }:
{
  options.dotfiles.platform.incusVm = {
    enable = lib.mkEnableOption "the Incus virtual machine guest platform";

    # Overrides for the guest agent feature map. Every feature the agent
    # understands is always written explicitly (see nixos.nix), because once a
    # feature map exists the agent disables everything not listed as true.
    agent.features = lib.mkOption {
      type = lib.types.attrsOf lib.types.bool;
      default = { };
      example = {
        exec = false;
        files = false;
      };
      description = "Incus guest agent features to enable or disable.";
    };
  };
}
