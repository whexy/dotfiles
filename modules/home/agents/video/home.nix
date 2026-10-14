# Video-editing toolkit. Agents cut a DaVinci Resolve timeline through
# Resolve Studio's own MCP server, which runs on the Windows host.
{ perSystem }:
{
  resolveMcp = perSystem.self.resolve-mcp;
}
