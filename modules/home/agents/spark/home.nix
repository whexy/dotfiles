{
  config,
  lib,
  perSystem,
  flake,
  mkTunnel,
  hostName,
}:
let
  cfg = config.dotfiles.agents.spark;

  # The Cloudflare tunnel proxies to this loopback port.
  port = 8765;

  log = "${config.home.homeDirectory}/Library/Logs/spark-mcp.log";

  # --spark stays at its default, the /usr/local/bin/spark symlink. Run by
  # the path that resolves to, inside the app bundle, the CLI cannot reach
  # Spark Desktop.
  serve = [
    (lib.getExe perSystem.self.spark-mcp)
    "--port"
    (toString port)
    # The Zero Trust organization whose Access application in front of the
    # hostname signs the assertions the server verifies.
    "--access-team-domain"
    "whexy.cloudflareaccess.com"
    "--access-aud"
    cfg.server.accessAud
  ];

  tunnel =
    let
      hostname = flake.lib.publicHost "spark" hostName;
    in
    mkTunnel {
      name = "spark-mcp-tunnel";
      tunnel = "spark-${hostName}";
      inherit hostname port;
      # Clients use only the MCP endpoint, so nothing else is published.
      path = "^/mcp$";
      description = "Cloudflare tunnel publishing spark-mcp at ${hostname}";
    };
in
{
  # spark-mcp spawns `spark mcp` per request, which talks to Spark Desktop in
  # the user's GUI session, so it runs as a user agent rather than a daemon.
  launchdAgents = lib.optionalAttrs cfg.server.enable (
    {
      spark-mcp = {
        enable = true;
        config = {
          ProgramArguments = serve;
          RunAtLoad = true;
          KeepAlive.SuccessfulExit = false;
          StandardOutPath = log;
          StandardErrorPath = log;
        };
      };
    }
    // tunnel.launchdAgents
  );
}
