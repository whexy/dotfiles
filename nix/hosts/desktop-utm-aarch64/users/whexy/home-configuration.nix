{ inputs, ... }:
let
  profile = import ../../profile.nix;
in
{
  imports = inputs.self.lib.homeModulesForCaps profile.caps;
}
