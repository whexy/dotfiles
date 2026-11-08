# Spark's mail tools for agents: the skill that drives the `spark` CLI Spark
# Desktop installs, and spark-mcp, which serves the same tools off this Mac.
args@{
  config,
  lib,
  pkgs,
  perSystem,
  flake,
  ...
}:
let
  cfg = config.dotfiles.agenticTooling.spark;

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
in
{
  config = lib.mkMerge [
    {
      assertions = [
        {
          # Spark Desktop runs only on macOS, and the tunnel's name comes from
          # the host, which standalone homes have no osConfig to supply.
          assertion = cfg.server.enable -> args.osConfig.nixpkgs.hostPlatform.isDarwin or false;
          message = "dotfiles.agenticTooling.spark.server.enable requires a nix-darwin host.";
        }
        {
          assertion = cfg.server.enable -> cfg.server.accessAud != null;
          message = "dotfiles.agenticTooling.spark.server.enable requires dotfiles.agenticTooling.spark.server.accessAud, the AUD tag of the host's Access application.";
        }
      ];
    }

    (lib.mkIf cfg.enable {
      dotfiles.agents.skills = import ./skills.nix { inherit pkgs perSystem flake; };
    })

    # spark-mcp spawns `spark mcp` per request, which talks to Spark Desktop
    # in the user's GUI session, so it runs as a user agent rather than a
    # daemon.
    (lib.mkIf cfg.server.enable {
      launchd.agents.spark-mcp = {
        enable = true;
        config = {
          ProgramArguments = serve;
          RunAtLoad = true;
          KeepAlive.SuccessfulExit = false;
          StandardOutPath = log;
          StandardErrorPath = log;
        };
      };

      dotfiles.tunnels.services.spark-mcp-tunnel = {
        service = "spark";
        inherit port;
        # Clients use only the MCP endpoint, so nothing else is published.
        path = "^/mcp$";
        description = "spark-mcp";
      };
    })
  ];
}
