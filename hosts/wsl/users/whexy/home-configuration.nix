{
  inputs,
  lib,
  ...
}:
{
  imports = [ inputs.self.homeModules.host-user ];

  # The dev cap gates the server on a Linux tailscaled, which WSL leaves to the
  # Windows client; `tailscale-wsl` lets `t3 serve` publish through that node.
  dotfiles.agents.t3code.server.enable = lib.mkForce true;
}
