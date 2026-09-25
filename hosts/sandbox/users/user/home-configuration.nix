# The home baked into packages/sandbox-image. Its files are linked into the
# image at build time and activation never runs: the sandbox has no root, no
# writable store, and no service manager.
{ inputs, lib, ... }:
{
  imports = [
    inputs.self.homeModules.all
  ]
  ++ inputs.self.lib.homeCapsModules [
    "base"
    "dev-lite"
  ];

  nixpkgs.config.allowUnfree = true;
  nixpkgs.overlays = [
    inputs.self.lib.overlays.unstable
    inputs.self.lib.overlays.llm-tools
  ];

  # Both only take effect through activation or a user service manager.
  dotfiles.nix.ghTokenFlakes.enable = lib.mkForce false;
  services.gpg-agent.enable = lib.mkForce false;
  nix.gc.automatic = lib.mkForce false;
}
