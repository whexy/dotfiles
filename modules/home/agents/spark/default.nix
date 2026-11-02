# Spark's mail tools for agents: the skill that drives the `spark` CLI Spark
# Desktop installs, and spark-mcp, which serves the same tools off this Mac.
args@{
  config,
  lib,
  perSystem,
  flake,
  ...
}:
let
  cfg = config.dotfiles.agents.spark;
  hostName = args.osConfig.dotfiles.host.hostName or null;

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
  options.dotfiles.agents.spark = {
    enable = lib.mkEnableOption "the Spark skill, which searches and reads mail through the `spark` CLI that Spark Desktop installs";
    server = {
      enable = lib.mkEnableOption ''
        spark-mcp, which serves Spark Desktop's email-reading tools to MCP
        clients off this Mac. A Cloudflare tunnel publishes it at
        `https://<host>-spark.clusters.work/mcp` (`flake.lib.publicHost`),
        behind a Cloudflare Access application that admits clients by
        OAuth or service token
      '';
      accessAud = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          AUD tag of the Cloudflare Access application covering this host's
          spark-mcp hostname. The server admits only requests carrying an
          Access assertion for it. The tag identifies the application; it
          is not a secret.
        '';
      };
    };
  };

  config = lib.mkIf config.dotfiles.agents.enable (
    lib.mkMerge [
      {
        assertions = [
          {
            # Spark Desktop runs only on macOS, and the tunnel's name comes from
            # the host, which standalone homes have no osConfig to supply.
            assertion = cfg.server.enable -> args.osConfig.nixpkgs.hostPlatform.isDarwin or false;
            message = "dotfiles.agents.spark.server.enable requires a nix-darwin host.";
          }
          {
            assertion = cfg.server.enable -> cfg.server.accessAud != null;
            message = "dotfiles.agents.spark.server.enable requires dotfiles.agents.spark.server.accessAud, the AUD tag of the host's Access application.";
          }
        ];
      }

      (lib.mkIf cfg.enable {
        dotfiles.agents.skills.local.spark = {
          source = ./skill;
          reason = ''
            The search-and-read part of `spark skill` from Spark 1.4.1, which
            Spark Desktop prints at runtime and no package ships. Compare
            against a newer CLI's output when its commands change.
          '';
        };
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

        dotfiles.tunnels.services.spark-mcp-tunnel =
          let
            hostname = flake.lib.publicHost "spark" hostName;
          in
          {
            tunnel = "spark-${hostName}";
            inherit hostname port;
            # Clients use only the MCP endpoint, so nothing else is published.
            path = "^/mcp$";
            description = "Cloudflare tunnel publishing spark-mcp at ${hostname}";
          };
      })
    ]
  );
}
