{ inputs, ... }:
{
  imports = with inputs.self.homeModules; [
    base
    dev-lite
    gui
  ];
}
