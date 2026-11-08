# The headless JADX MCP server's JAR, which REA's Android provider runs. REA
# documents the one version it supports (android-applications.md in its
# skill).
{ pkgs }:
pkgs.fetchurl {
  url = "https://github.com/1013503897/jadx-headless-mcp/releases/download/v0.7.1/jadx-headless-mcp-0.7.1-all.jar";
  hash = "sha256-bl6s9QC2QpK/tzxJeXwZWPbuRGRuQ+hoA5rn/rVz/3U=";
  # Moves only with a rea-agents release that supports another version.
  passthru.updater = null;
  meta = {
    description = "Headless JADX MCP server, as the JAR REA's Android provider runs";
    homepage = "https://github.com/1013503897/jadx-headless-mcp";
    license = pkgs.lib.licenses.asl20;
  };
}
