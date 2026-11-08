# Incus virtual machine guest platform.
{ lib, ... }:
{
  options.dotfiles.platform.incusVm = {
    enable = lib.mkEnableOption "the Incus virtual machine guest platform";

    untrustedHypervisor = lib.mkEnableOption ''
      a hypervisor that is not fully trusted: the guest agent turns off every
      API that can execute commands or read guest files (which would expose
      agenix secrets under /run/agenix), and interface state (VM IPs in
      `incus list`)
    '';

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

    encryptedDisk.enable = lib.mkEnableOption ''
      a LUKS-encrypted system disk, built into a `<hostName>.qcow2` image by
      `just build-incus-vm <hostName>`, which asks for the passphrase
    '';
  };
}
