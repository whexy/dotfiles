{
  inputs,
  lib,
  perSystem,
  ...
}:
{
  imports = [ inputs.self.homeModules.host-user ];

  # The dev cap gates the server on a Linux tailscaled, which WSL leaves to the
  # Windows client; `tailscale-wsl` lets `t3 serve` publish through that node.
  # t3-pair comes without the desktop option so no Electron app is installed.
  dotfiles.agents.t3code.server.enable = lib.mkForce true;
  home.packages = [ perSystem.self.t3-pair ];
}
