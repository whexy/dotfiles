# Add llm-agents packages as pkgs.llm-agents
# Requires: inputs.llm-agents
{ llm-agents }:
_final: prev:
let
  upstream = llm-agents.packages.${prev.stdenv.hostPlatform.system};
in
{
  llm-agents = upstream // {
    # Build pi as a Node package instead of a Bun-compiled binary.
    #
    # pi-subagents spawns background children as a separate Node process that
    # imports pi's host modules, so it needs pi on disk as a real npm package.
    # The Bun binary embeds every module and reports process.argv[1] as
    # /$bunfs/root/pi, so the extension resolves no package root and no host
    # peer packages, and every async launch fails with "Background children
    # require pi installed as the npm package". Only foreground (async: false)
    # subagents work in that layout.
    #
    # Node mode costs roughly 210 MiB of extra closure and drops the binary's
    # Bun runtime; it is only needed for hosts that run pi subagents.
    pi = upstream.pi.override { useBun = false; };
  };
}
