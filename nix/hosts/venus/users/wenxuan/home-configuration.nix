{ inputs, ... }:
{
  imports = [
    inputs.self.homeModules.base
    inputs.self.homeModules.dev
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
  targets.genericLinux.enable = true;
  targets.genericLinux.gpu.enable = false;
}
