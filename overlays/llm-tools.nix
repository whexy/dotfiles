# Add llm-agents packages as pkgs.llm-agents
# Requires: inputs.llm-agents
{ llm-agents }:
_final: prev:
let
  upstream = llm-agents.packages.${prev.stdenv.hostPlatform.system};
in
{
  llm-agents = upstream // {
    codex = prev.callPackage ./codex-package.nix { inherit (upstream) codex; };
  };
}
