# The agenix identity of github:whexy/clusters-work, whose dev shell passes
# it to agenix from this path (its docs/secrets.md#editing). This copy is the
# key's only escrow: that repository's dev-key-only secrets are lost with it.
{ config, lib, ... }:
{
  config = lib.mkIf config.dotfiles.tooling.clustersWorkKey.enable {
    age.secrets.clusters-work-devkey.file = ../../../secrets/clusters-work-devkey.age;
  };
}
