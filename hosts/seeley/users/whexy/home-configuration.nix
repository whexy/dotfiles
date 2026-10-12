{ inputs, ... }:
{
  imports = [ inputs.self.homeModules.host-user ];

  dotfiles = {
    panel.linuxBar = "eww";
    # Only this host: Ghidra brings REA's closure to about 2 GiB.
    agents.rea.enable = true;
  };
}
