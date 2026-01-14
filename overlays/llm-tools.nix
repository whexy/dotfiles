# Add llm-agents packages as pkgs.llm-agents
# Requires: inputs.llm-agents
{ llm-agents }:
final: prev: {
  llm-agents = llm-agents.packages.${prev.system};
}
