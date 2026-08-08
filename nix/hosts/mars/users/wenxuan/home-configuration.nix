{ inputs, ... }:
{
  imports = [
    inputs.self.homeModules.base
    inputs.self.homeModules.dev
    inputs.self.homeModules.auto-upgrade
  ];
  nixpkgs.config.allowUnfree = true;
  nixpkgs.overlays = [
    inputs.self.lib.overlays.unstable
    inputs.self.lib.overlays.llm-tools
  ];
  _module.args = {
    darwin = false;
    wsl = false;
  };
  # Not connected to the tailnet (no Tailscale on this host).
  dotfiles.tailscale = false;

  dotfiles.autoUpgrade.enable = true;

  targets.genericLinux.enable = true;
  targets.genericLinux.gpu.enable = false;
  home.homeDirectory = "/data/wenxuan";
}
